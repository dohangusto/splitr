import CloudKit
import Foundation
import OSLog
import SplitBillCore

/// CloudKit implementation of `RoomSyncService`.
///
/// Layout: each room is a custom zone ("room-<uuid>") in the host's private
/// database, shared to members via a zone-wide `CKShare`. Rooms the user
/// joined live in the shared database under the host's owner name.
///
/// Sync strategy: explicit operations with per-zone change tokens (not
/// CKSyncEngine — we need per-record optimistic locking on claim writes so
/// a lost race surfaces as `serverRecordChanged`, and not SwiftData sync,
/// which CLAUDE.md forbids). Fetched records are cached per zone so
/// incremental changes rebuild whole `Room` values.
public actor CloudKitRoomSync: RoomSyncService {

    private let container: CKContainer
    private let privateDB: CKDatabase
    private let sharedDB: CKDatabase

    /// Server records by zone — the source of change tags for CAS saves.
    private var recordsByZone: [CKRecordZone.ID: [CKRecord.ID: CKRecord]] = [:]
    /// Which database each known zone lives in (private = hosted by me).
    private var zoneDatabase: [CKRecordZone.ID: CKDatabase] = [:]
    private let tokens: ChangeTokenStore

    public nonisolated let updates: AsyncStream<SyncUpdate>
    private let updatesContinuation: AsyncStream<SyncUpdate>.Continuation

    public init(containerIdentifier: String = RecordSchema.containerIdentifier) {
        container = CKContainer(identifier: containerIdentifier)
        privateDB = container.privateCloudDatabase
        sharedDB = container.sharedCloudDatabase
        tokens = ChangeTokenStore()
        (updates, updatesContinuation) = AsyncStream.makeStream(of: SyncUpdate.self)
    }

    // MARK: - Bootstrap

    public func bootstrap() async throws {
        let status = try await container.accountStatus()
        guard status == .available else { throw SyncError.notSignedIn }
        try await installDatabaseSubscriptions()
    }

    private func installDatabaseSubscriptions() async throws {
        for (database, id) in [(privateDB, "private-db-changes"), (sharedDB, "shared-db-changes")] {
            let subscription = CKDatabaseSubscription(subscriptionID: CKSubscription.ID(id))
            let info = CKSubscription.NotificationInfo()
            info.shouldSendContentAvailable = true // silent push
            subscription.notificationInfo = info
            _ = try await database.modifySubscriptions(saving: [subscription], deleting: [])
        }
    }

    // MARK: - Fetch

    public func fetchRooms() async throws -> [Room] {
        try await fetchChanges(in: privateDB)
        try await fetchChanges(in: sharedDB)
        return assembleRooms()
    }

    private func fetchChanges(in database: CKDatabase) async throws {
        var moreComing = true
        while moreComing {
            let changes = try await database.databaseChanges(since: tokens.databaseToken(for: database.databaseScope))
            for modification in changes.modifications where RecordSchema.roomID(fromZoneName: modification.zoneID.zoneName) != nil {
                zoneDatabase[modification.zoneID] = database
                try await fetchZoneChanges(modification.zoneID, in: database)
            }
            for deletion in changes.deletions {
                recordsByZone[deletion.zoneID] = nil
                zoneDatabase[deletion.zoneID] = nil
                tokens.setZoneToken(nil, for: deletion.zoneID)
            }
            tokens.setDatabaseToken(changes.changeToken, for: database.databaseScope)
            moreComing = changes.moreComing
        }
    }

    private func fetchZoneChanges(_ zoneID: CKRecordZone.ID, in database: CKDatabase) async throws {
        var moreComing = true
        while moreComing {
            let changes: (
                modificationResultsByID: [CKRecord.ID: Result<CKDatabase.RecordZoneChange.Modification, any Error>],
                deletions: [CKDatabase.RecordZoneChange.Deletion],
                changeToken: CKServerChangeToken,
                moreComing: Bool
            )
            do {
                changes = try await database.recordZoneChanges(
                    inZoneWith: zoneID,
                    since: tokens.zoneToken(for: zoneID)
                )
            } catch let error as CKError where error.code == .changeTokenExpired {
                tokens.setZoneToken(nil, for: zoneID)
                recordsByZone[zoneID] = [:]
                continue
            }
            var zoneRecords = recordsByZone[zoneID] ?? [:]
            for (recordID, result) in changes.modificationResultsByID {
                if let modification = try? result.get() {
                    zoneRecords[recordID] = modification.record
                }
            }
            for deletion in changes.deletions {
                zoneRecords[deletion.recordID] = nil
            }
            recordsByZone[zoneID] = zoneRecords
            tokens.setZoneToken(changes.changeToken, for: zoneID)
            moreComing = changes.moreComing
        }
    }

    private func assembleRooms() -> [Room] {
        recordsByZone.compactMap { _, records in
            try? RecordMapper.room(from: Array(records.values))
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: - Save

    /// Preflight: can this account host at all? Quota problems only show up
    /// on write, but signed-out / managed / degraded accounts fail here.
    public func hostingIssue() async -> HostingIssue? {
        do {
            let status = try await container.accountStatus()
            Self.logger.info("hosting preflight: accountStatus=\(status.rawValue)")
            switch status {
            case .available:
                return nil
            case .noAccount:
                return .notSignedIn
            case .restricted:
                return .managedAccount
            case .temporarilyUnavailable:
                return .temporarilyUnavailable
            case .couldNotDetermine:
                return nil // let the write attempt produce the real error
            @unknown default:
                return nil
            }
        } catch {
            Self.logger.error("hosting preflight failed: \(error.localizedDescription)")
            return nil
        }
    }

    public func create(room: Room) async throws {
        let zoneID = CKRecordZone.ID(zoneName: RecordSchema.zoneName(roomID: room.id), ownerName: CKCurrentUserDefaultName)
        do {
            _ = try await privateDB.modifyRecordZones(saving: [CKRecordZone(zoneID: zoneID)], deleting: [])
            zoneDatabase[zoneID] = privateDB
            let records = RecordMapper.records(for: room, zoneID: zoneID)
            let results = try await privateDB.modifyRecords(saving: records, deleting: [], savePolicy: .ifServerRecordUnchanged, atomically: true)
            try cache(saveResults: results.saveResults, zoneID: zoneID)
        } catch {
            let status = (try? await container.accountStatus()).map { "\($0.rawValue)" } ?? "?"
            Self.logger.error("create room failed (accountStatus=\(status)): \(Self.describe(error))")
            if let (issue, code) = Self.hostingIssue(from: error) {
                throw SyncError.hostingFailed(issue, ckCode: code)
            }
            throw SyncError.underlying(error)
        }
    }

    /// Maps a create-room failure to an account-level hosting issue.
    /// Unwraps partial-failure containers to find the real per-record code.
    static func hostingIssue(from error: Error) -> (HostingIssue, Int?)? {
        guard let ckError = deepestCKError(error) else { return nil }
        let code = ckError.code.rawValue
        switch ckError.code {
        case .quotaExceeded:
            return (.quotaExceeded, code)
        case .managedAccountRestricted, .permissionFailure:
            return (.managedAccount, code)
        case .notAuthenticated:
            return (.notSignedIn, code)
        case .accountTemporarilyUnavailable, .serviceUnavailable, .requestRateLimited, .zoneBusy:
            return (.temporarilyUnavailable, code)
        case .networkUnavailable, .networkFailure:
            return (.network, code)
        default:
            return (.unknown(String(describing: ckError.code)), code)
        }
    }

    private static func deepestCKError(_ error: Error) -> CKError? {
        guard let ckError = error as? CKError else { return nil }
        if let partial = ckError.partialErrorsByItemID?.values
            .compactMap({ $0 as? CKError })
            .first(where: { $0.code != .batchRequestFailed }) {
            return partial
        }
        return ckError
    }

    private static func describe(_ error: Error) -> String {
        if let ckError = deepestCKError(error) {
            return "CKError \(ckError.code.rawValue) (\(String(describing: ckError.code))): \(ckError.localizedDescription)"
        }
        return error.localizedDescription
    }

    private static let logger = Logger(subsystem: "com.c4.splitr", category: "CloudKitSync")

    /// Non-claim intents: diff the mutated room against the cached server
    /// records, save changed records, delete removed ones. Any race throws
    /// `staleState` with a refetched authoritative room.
    public func push(room: Room) async throws {
        let (zoneID, database) = try zone(for: room.id)
        let cached = recordsByZone[zoneID] ?? [:]
        let desired = RecordMapper.records(for: room, zoneID: zoneID)

        var toSave: [CKRecord] = []
        for record in desired {
            if let existing = cached[record.recordID] {
                let updated = merge(fields: record, onto: existing)
                if updated != nil { toSave.append(updated!) }
            } else {
                toSave.append(record)
            }
        }
        let desiredIDs = Set(desired.map(\.recordID))
        let toDelete = cached.keys.filter { !desiredIDs.contains($0) && cached[$0]?.recordType != CKRecord.SystemType.share }

        guard !toSave.isEmpty || !toDelete.isEmpty else { return }
        do {
            let results = try await database.modifyRecords(
                saving: toSave,
                deleting: Array(toDelete),
                savePolicy: .ifServerRecordUnchanged,
                atomically: true
            )
            try cache(saveResults: results.saveResults, zoneID: zoneID)
            for id in toDelete { recordsByZone[zoneID]?[id] = nil }
        } catch {
            if isServerRecordChanged(error) {
                try await fetchZoneChanges(zoneID, in: database)
                throw SyncError.staleState(serverRoom: try currentRoom(in: zoneID))
            }
            throw SyncError.underlying(error)
        }
    }

    /// Claim writes: optimistic-locking save of the single item record.
    /// A lost race maps to `SyncError.conflict` carrying the winners.
    public func pushClaim(room: Room, billID: UUID, itemID: UUID) async throws {
        let (zoneID, database) = try zone(for: room.id)
        guard let item = room.bill(withID: billID)?.item(withID: itemID) else { return }
        let recordID = RecordMapper.recordID(itemID, zoneID: zoneID)
        guard let cached = recordsByZone[zoneID]?[recordID] else {
            // Never fetched this record — full push will create it.
            try await push(room: room)
            return
        }
        let record = cached.copy() as! CKRecord
        RecordMapper.applyClaimState(item.claimState, to: record)

        do {
            let results = try await database.modifyRecords(
                saving: [record],
                deleting: [],
                savePolicy: .ifServerRecordUnchanged,
                atomically: true
            )
            try cache(saveResults: results.saveResults, zoneID: zoneID)
        } catch {
            guard isServerRecordChanged(error) else { throw SyncError.underlying(error) }
            // Lost the race: refetch the zone and surface who holds the item.
            try await fetchZoneChanges(zoneID, in: database)
            let serverRoom = try currentRoom(in: zoneID)
            let claimers = serverRoom.bill(withID: billID)?
                .item(withID: itemID)?.claimState.claimerIDs ?? []
            throw SyncError.conflict(SyncConflict(
                itemID: itemID,
                claimerIDs: claimers,
                serverRoom: serverRoom
            ))
        }
    }

    // MARK: - Sharing

    public func shareURL(roomID: UUID) async throws -> URL {
        let (zoneID, database) = try zone(for: roomID)
        let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)

        if let existing = try? await database.record(for: shareID) as? CKShare {
            if existing.publicPermission == .readWrite, let url = existing.url {
                return url
            }
            // Repair shares created before link-based access was set:
            // with .none, every link tap fails with "the owner stopped
            // sharing" for anyone not explicitly invited.
            existing.publicPermission = .readWrite
            return try await saveShare(existing, in: database, zoneID: zoneID)
        }

        let share = CKShare(recordZoneID: zoneID)
        // Link-based joining: anyone with the URL becomes a participant with
        // write access (they add their Member record and claim items).
        // Identity shown in the app is our Member record, never the Apple ID.
        share.publicPermission = .readWrite
        share[CKShare.SystemFieldKey.title] = "splitr room" as CKRecordValue
        return try await saveShare(share, in: database, zoneID: zoneID)
    }

    /// Saves the share and returns its URL only from the *server-confirmed*
    /// record — a URL read before the save completes points at a share the
    /// server doesn't have yet.
    private func saveShare(_ share: CKShare, in database: CKDatabase, zoneID: CKRecordZone.ID) async throws -> URL {
        let results = try await database.modifyRecords(
            saving: [share],
            deleting: [],
            savePolicy: .ifServerRecordUnchanged,
            atomically: true
        )
        try cache(saveResults: results.saveResults, zoneID: zoneID)
        guard let saved = try results.saveResults[share.recordID]?.get() as? CKShare,
              let url = saved.url else {
            throw SyncError.underlying(CKError(.internalError))
        }
        return url
    }

    public func acceptShare(from url: URL) async throws {
        let metadata = try await container.shareMetadata(for: url)
        try await acceptShare(metadata: metadata)
    }

    public func acceptShare(metadata: CKShare.Metadata) async throws {
        _ = try await container.accept(metadata)
        // The zone now exists in our shared database; pull it in.
        try await fetchChanges(in: sharedDB)
        updatesContinuation.yield(.rooms(assembleRooms()))
    }

    // MARK: - Push notifications

    public func fetchRemoteChanges() async -> Bool {
        do {
            let rooms = try await fetchRooms()
            updatesContinuation.yield(.rooms(rooms))
            return true
        } catch {
            return false
        }
    }

    // MARK: - Helpers

    private func zone(for roomID: UUID) throws -> (CKRecordZone.ID, CKDatabase) {
        let zoneName = RecordSchema.zoneName(roomID: roomID)
        if let match = zoneDatabase.first(where: { $0.key.zoneName == zoneName }) {
            return (match.key, match.value)
        }
        // Not yet fetched — assume a zone we host.
        let zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
        return (zoneID, privateDB)
    }

    private func currentRoom(in zoneID: CKRecordZone.ID) throws -> Room {
        try RecordMapper.room(from: Array((recordsByZone[zoneID] ?? [:]).values))
    }

    private func cache(saveResults: [CKRecord.ID: Result<CKRecord, any Error>], zoneID: CKRecordZone.ID) throws {
        var zoneRecords = recordsByZone[zoneID] ?? [:]
        for (id, result) in saveResults {
            zoneRecords[id] = try result.get()
        }
        recordsByZone[zoneID] = zoneRecords
    }

    /// Applies desired field values onto a copy of the cached server record
    /// (keeping its change tag). Returns nil when nothing differs.
    private func merge(fields desired: CKRecord, onto existing: CKRecord) -> CKRecord? {
        let copy = existing.copy() as! CKRecord
        var changed = false
        for key in desired.allKeys() {
            let new = desired[key]
            let old = copy[key]
            if !valuesEqual(new, old) {
                copy[key] = new
                changed = true
            }
        }
        return changed ? copy : nil
    }

    private func valuesEqual(_ a: Any?, _ b: Any?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case (let a?, let b?):
            return (a as? NSObject)?.isEqual(b as? NSObject) ?? false
        default: return false
        }
    }

    private func isServerRecordChanged(_ error: Error) -> Bool {
        guard let ckError = error as? CKError else { return false }
        if ckError.code == .serverRecordChanged { return true }
        if let partial = ckError.partialErrorsByItemID?.values {
            return partial.contains { ($0 as? CKError)?.code == .serverRecordChanged }
        }
        return false
    }
}

/// Persists CloudKit change tokens across launches (UserDefaults-backed).
final class ChangeTokenStore: @unchecked Sendable {
    private let defaults = UserDefaults.standard
    private let queue = DispatchQueue(label: "splitr.tokens")

    func databaseToken(for scope: CKDatabase.Scope) -> CKServerChangeToken? {
        token(key: "ck-db-token-\(scope.rawValue)")
    }

    func setDatabaseToken(_ token: CKServerChangeToken?, for scope: CKDatabase.Scope) {
        set(token, key: "ck-db-token-\(scope.rawValue)")
    }

    func zoneToken(for zoneID: CKRecordZone.ID) -> CKServerChangeToken? {
        token(key: "ck-zone-token-\(zoneID.ownerName)-\(zoneID.zoneName)")
    }

    func setZoneToken(_ token: CKServerChangeToken?, for zoneID: CKRecordZone.ID) {
        set(token, key: "ck-zone-token-\(zoneID.ownerName)-\(zoneID.zoneName)")
    }

    private func token(key: String) -> CKServerChangeToken? {
        queue.sync {
            guard let data = defaults.data(forKey: key) else { return nil }
            return try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data)
        }
    }

    private func set(_ token: CKServerChangeToken?, key: String) {
        queue.sync {
            guard let token,
                  let data = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) else {
                defaults.removeObject(forKey: key)
                return
            }
            defaults.set(data, forKey: key)
        }
    }
}
