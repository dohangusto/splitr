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
        push { [sync] in try await sync.create(room: room) }
        return room
    }

    func joinMember(named name: String, emoji: String, roomID: UUID) {
        mutate(roomID) { room, _ in
            try room.join(Member(displayName: name, avatarEmoji: emoji))
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

    func markPaid(roomID: UUID) {
        mutate(roomID) { room, actor in try room.markPaid(as: actor) }
    }

    func confirmPayment(of memberID: UUID, roomID: UUID) {
        mutate(roomID) { room, actor in try room.confirmPayment(of: memberID, by: actor) }
    }

    // MARK: - Sharing & push entry points (beyond RoomStoring)

    /// Host-side: the CKShare invitation URL for a room.
    func inviteURL(roomID: UUID) async -> URL? {
        do {
            return try await sync.shareURL(roomID: roomID)
        } catch {
            alert = StoreAlert(message: "Couldn't create the invite link. Check your iCloud connection.")
            return nil
        }
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
    func handleRemoteNotification(userInfo: [AnyHashable: Any]) async -> Bool {
        await sync.handleRemoteNotification(userInfo: userInfo)
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

    private func push(_ operation: @escaping @Sendable () async throws -> Void) {
        let task = Task { [weak self] in
            do {
                try await operation()
            } catch {
                await MainActor.run { self?.handlePersistError(error) }
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
        default:
            alert = StoreAlert(message: "Couldn't sync that change. It will show only on this device.")
        }
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
