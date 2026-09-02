import Foundation
import Observation
import SplitBillCore
import SplitBillSync

/// CloudKit-backed implementation of `RoomStoring`. Views are unchanged:
/// they see the same protocol as the mock store.
///
/// Strategy: intents apply optimistically through Core's throwing API
/// (instant UI), then persist asynchronously via `RoomSyncService`.
/// A lost claim race (`serverRecordChanged` under the hood) arrives as
/// `SyncError.conflict`: local state reconciles to the authoritative
/// server room and the alert shows "Already claimed by <names>" — the
/// exact same copy as the mock store's local conflicts.
@Observable
final class CloudKitRoomStore: RoomStoring {
    private(set) var rooms: [Room] = []
    var alert: StoreAlert?
    /// True until the first fetch settles (success or failure), so launch
    /// shows "loading" instead of a false "no rooms yet".
    private(set) var isLoadingRooms = true

    private var actingByRoom: [UUID: UUID] = [:]
    private let sync: any RoomSyncService
    /// In-flight persistence work; tests await `waitForPushes()`.
    private var pendingPushes: [Task<Void, Never>] = []

    init(sync: any RoomSyncService = CloudKitRoomSync()) {
        self.sync = sync
        Task { await start() }
    }

    private func start() async {
        do {
            try await sync.bootstrap()
            rooms = try await sync.fetchRooms()
        } catch SyncError.notSignedIn {
            alert = StoreAlert(message: "Sign in to iCloud in Settings to create and join rooms.")
        } catch {
            alert = StoreAlert(message: "Couldn't reach iCloud. Your changes will not sync yet.")
        }
        isLoadingRooms = false
        for await update in sync.updates {
            if case .rooms(let serverRooms) = update {
                rooms = serverRooms
            }
        }
    }

    // MARK: - RoomStoring queries

    func room(withID id: UUID) -> Room? {
        rooms.first { $0.id == id }
    }

    func actingMemberID(in roomID: UUID) -> UUID? {
        if let acting = actingByRoom[roomID],
           room(withID: roomID)?.member(withID: acting) != nil {
            return acting
        }
        return room(withID: roomID)?.hostMemberID
    }

    func setActingMember(_ memberID: UUID, in roomID: UUID) {
        actingByRoom[roomID] = memberID
    }

    // MARK: - Intents

    @discardableResult
    func createRoom(named name: String, hostName: String, hostEmoji: String) -> Room {
        let host = Member(displayName: hostName, avatarEmoji: hostEmoji, isHost: true)
        let room = Room(name: name, host: host)
        rooms.insert(room, at: 0)
        // If the create can't reach CloudKit, the local room is removed
        // again (no phantom local-only rooms) and the alert says exactly
        // why — hosting failures never block joining someone else's room.
        push(removingOnFailure: room.id) { [sync] in
            if let issue = await sync.hostingIssue() {
                throw SyncError.hostingFailed(issue, ckCode: nil)
            }
            try await sync.create(room: room)
        }
        return room
    }

    func joinMember(named name: String, emoji: String, roomID: UUID) {
        mutate(roomID) { room, _ in
            try room.join(Member(displayName: name, avatarEmoji: emoji))
        }
    }

    func joinFromInvite(named name: String, emoji: String, roomID: UUID) {
        guard room(withID: roomID) != nil else { return }
        let defaults = UserDefaults.standard
        let key = "splitr.invite_member.\(roomID.uuidString)"
        let memberID = defaults.string(forKey: key).flatMap(UUID.init) ?? UUID()
        defaults.set(memberID.uuidString, forKey: key)
        let member = Member(id: memberID, displayName: name, avatarEmoji: emoji)
        if self.room(withID: roomID)?.member(withID: memberID) != nil {
            setActingMember(memberID, in: roomID)
            return
        }
        mutate(roomID) { room, _ in
            try room.join(member)
        }
        if self.room(withID: roomID)?.member(withID: memberID) != nil {
            setActingMember(memberID, in: roomID)
        }
    }

    func renameRoom(roomID: UUID, to newName: String) {
        mutate(roomID) { room, _ in
            room.name = newName
        }
    }

    func advance(roomID: UUID) {
        mutate(roomID) { room, actor in try room.advance(by: actor) }
    }

    func rollbackToClaiming(roomID: UUID) {
        mutate(roomID) { room, actor in try room.rollbackToClaiming(by: actor) }
    }

    func kick(memberID: UUID, roomID: UUID) {
        mutate(roomID) { room, actor in try room.kick(memberID: memberID, by: actor) }
    }

    func addBill(_ bill: Bill, roomID: UUID) {
        mutate(roomID) { room, actor in try room.addBill(bill, by: actor) }
    }

    // Full-room push diffs against the cached records, so replaced or
    // removed items become CKRecord deletes — no orphans left in the zone.
    func updateBill(_ bill: Bill, roomID: UUID) {
        mutate(roomID) { room, actor in try room.updateBill(bill, by: actor) }
    }

    func removeBill(billID: UUID, roomID: UUID) {
        mutate(roomID) { room, actor in try room.removeBill(withID: billID, by: actor) }
    }

    func claim(itemID: UUID, billID: UUID, roomID: UUID) {
        mutate(roomID, persist: .claim(billID: billID, itemID: itemID)) { room, actor in
            try room.claim(itemID: itemID, in: billID, as: actor)
        }
    }

    func joinClaim(itemID: UUID, billID: UUID, roomID: UUID) {
        mutate(roomID, persist: .claim(billID: billID, itemID: itemID)) { room, actor in
            try room.joinClaim(itemID: itemID, in: billID, as: actor)
        }
    }

    func releaseClaim(itemID: UUID, billID: UUID, roomID: UUID) {
        mutate(roomID, persist: .claim(billID: billID, itemID: itemID)) { room, actor in
            try room.releaseClaim(itemID: itemID, in: billID, as: actor)
        }
    }

    func forceAssign(itemID: UUID, billID: UUID, to memberID: UUID, roomID: UUID) {
        mutate(roomID, persist: .claim(billID: billID, itemID: itemID)) { room, actor in
            try room.forceAssign(itemID: itemID, in: billID, to: memberID, by: actor)
        }
    }

    func toggleClaim(itemID: UUID, billID: UUID, for memberID: UUID, roomID: UUID) {
        mutate(roomID, persist: .claim(billID: billID, itemID: itemID)) { room, _ in
            try room.toggleClaim(itemID: itemID, in: billID, for: memberID)
        }
    }

    func markPaid(roomID: UUID) {
        mutate(roomID) { room, actor in try room.markPaid(as: actor) }
    }

    func confirmPayment(of memberID: UUID, roomID: UUID) {
        mutate(roomID) { room, actor in try room.confirmPayment(of: memberID, by: actor) }
    }

    // MARK: - Sharing & push entry points (beyond RoomStoring)

    /// Pre-create hosting check for the Home screen: returns the actionable
    /// message when this account can't host (quota, managed Apple ID, not
    /// signed in, …), nil when hosting looks healthy. Joining is unaffected.
    func hostingIssueMessage() async -> String? {
        guard let issue = await sync.hostingIssue() else { return nil }
        return Self.hostingMessage(for: issue, ckCode: nil)
    }

    /// Host-side: the CKShare invitation URL for a room.
    func inviteURL(roomID: UUID) async -> URL? {
        do {
            return try await sync.shareURL(roomID: roomID)
        } catch {
            alert = StoreAlert(message: "Couldn't create the invite link. Check your iCloud connection.")
            return nil
        }
    }

    /// Host-side (proximity join): adds a member with a host-assigned ID.
    /// Room state still flows only through CloudKit — this is a normal
    /// member-record write, not a peer-to-peer state path.
    func addMember(_ member: Member, roomID: UUID) {
        mutate(roomID) { room, _ in
            try room.join(member)
        }
    }

    /// Member-side (proximity join): accepts the CKShare from its URL —
    /// the same acceptance path as tapping an invite link.
    @discardableResult
    func acceptShare(from url: URL) async -> Bool {
        do {
            try await sync.acceptShare(from: url)
            return true
        } catch {
            alert = StoreAlert(message: "Couldn't join that room. Ask the host for a new invite link.")
            return false
        }
    }

    func waitForRoom(id: UUID) async -> Bool {
        await waitForRoom(id: id, timeout: 30)
    }

    func resetAllData() {
        rooms.removeAll()
        alert = nil
        actingByRoom.removeAll()
        pendingPushes.forEach { $0.cancel() }
        pendingPushes = []
    }

    func deleteRoom(roomID: UUID) {
        rooms.removeAll { $0.id == roomID }
    }

    /// Waits (with periodic refetches) until a just-joined room syncs in.
    func waitForRoom(id: UUID, timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if room(withID: id) != nil { return true }
            _ = await sync.fetchRemoteChanges()
            try? await Task.sleep(for: .milliseconds(700))
        }
        return room(withID: id) != nil
    }

    /// Member-side: called when the app opens a CKShare invitation.
    func acceptShare(metadata: ShareMetadata) async {
        do {
            try await sync.acceptShare(metadata: metadata)
        } catch {
            alert = StoreAlert(message: "Couldn't join that room. Ask the host for a new invite link.")
        }
    }

    /// Silent-push entry: fetches remote changes; snapshots arrive on `updates`.
    @discardableResult
    func refetchFromPush() async -> Bool {
        await sync.fetchRemoteChanges()
    }

    // MARK: - Persistence plumbing

    private enum PersistKind {
        case fullRoom
        case claim(billID: UUID, itemID: UUID)
    }

    private func mutate(
        _ roomID: UUID,
        persist kind: PersistKind = .fullRoom,
        _ body: (inout Room, _ actor: UUID) throws -> Void
    ) {
        guard let index = rooms.firstIndex(where: { $0.id == roomID }) else { return }
        let actor = actingMemberID(in: roomID) ?? rooms[index].hostMemberID
        do {
            try body(&rooms[index], actor)
        } catch {
            alert = StoreAlert(message: StoreCopy.message(for: error, in: rooms[index]))
            return
        }
        let room = rooms[index]
        push { [sync] in
            switch kind {
            case .fullRoom:
                try await sync.push(room: room)
            case .claim(let billID, let itemID):
                try await sync.pushClaim(room: room, billID: billID, itemID: itemID)
            }
        }
    }

    private func push(
        removingOnFailure roomID: UUID? = nil,
        _ operation: @escaping @Sendable () async throws -> Void
    ) {
        let task = Task { [weak self] in
            do {
                try await operation()
            } catch {
                await MainActor.run {
                    if let roomID {
                        self?.rooms.removeAll { $0.id == roomID }
                    }
                    self?.handlePersistError(error)
                }
            }
        }
        pendingPushes.append(task)
    }

    private func handlePersistError(_ error: Error) {
        switch error {
        case SyncError.conflict(let conflict):
            // Reconcile to the server's truth, then surface the same
            // "Already claimed by <names>" the local path produces.
            reconcile(conflict.serverRoom)
            alert = StoreAlert(message: StoreCopy.message(
                for: ClaimError.alreadyClaimed(itemID: conflict.itemID, claimers: conflict.claimerIDs),
                in: conflict.serverRoom
            ))
        case SyncError.staleState(let serverRoom):
            reconcile(serverRoom)
            alert = StoreAlert(message: "Someone else changed the room — it's been refreshed.")
        case SyncError.notSignedIn:
            alert = StoreAlert(message: "Sign in to iCloud in Settings to sync this room.")
        case SyncError.hostingFailed(let issue, let ckCode):
            alert = StoreAlert(message: Self.hostingMessage(for: issue, ckCode: ckCode))
        default:
            alert = StoreAlert(message: "Couldn't sync that change. It will show only on this device.")
        }
    }

    /// Actionable copy per hosting failure. All of these users can still
    /// JOIN rooms, so the copy always points there. The CKError code is
    /// appended so failures are diagnosable during on-device testing.
    static func hostingMessage(for issue: HostingIssue, ckCode: Int?) -> String {
        let body = switch issue {
        case .quotaExceeded:
            "Your iCloud storage is full, so this room can't be hosted. Free up space in Settings → iCloud, or join a room someone else hosts."
        case .managedAccount:
            "This Apple ID is managed by a school or organization and can't host shared rooms. You can still join rooms someone else hosts."
        case .notSignedIn:
            "Sign in to iCloud in Settings to host rooms. You can still join rooms via an invite."
        case .temporarilyUnavailable:
            "iCloud is temporarily unavailable for your account. Wait a minute and try creating the room again."
        case .network:
            "No internet connection. Connect and try creating the room again."
        case .unknown(let codeDescription):
            "Couldn't create the room (CloudKit: \(codeDescription)). You can still join rooms someone else hosts."
        }
        guard let ckCode else { return body }
        return body + " [CKError \(ckCode)]"
    }

    private func reconcile(_ serverRoom: Room) {
        if let index = rooms.firstIndex(where: { $0.id == serverRoom.id }) {
            rooms[index] = serverRoom
        } else {
            rooms.insert(serverRoom, at: 0)
        }
    }

    /// Test hook: waits for all in-flight persistence tasks.
    func waitForPushes() async {
        let tasks = pendingPushes
        pendingPushes = []
        for task in tasks {
            await task.value
        }
    }
}
