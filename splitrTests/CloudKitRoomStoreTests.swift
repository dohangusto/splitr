import Foundation
import Testing
import SplitBillCore
import SplitBillSync
@testable import splitr

/// A scripted `RoomSyncService`: no CloudKit, no network. Lets tests drive
/// the CloudKit store's optimistic-apply / conflict-reconcile logic.
final class FakeSyncService: RoomSyncService, @unchecked Sendable {
    var bootstrapError: Error?
    var initialRooms: [Room] = []
    /// When set, the next `pushClaim` loses the race with this conflict.
    var nextClaimConflict: SyncConflict?
    var pushedRooms: [Room] = []
    var pushedClaims: [(roomID: UUID, billID: UUID, itemID: UUID)] = []

    let updates: AsyncStream<SyncUpdate>
    private let continuation: AsyncStream<SyncUpdate>.Continuation

    init() {
        (updates, continuation) = AsyncStream.makeStream(of: SyncUpdate.self)
    }

    func emit(_ update: SyncUpdate) {
        continuation.yield(update)
    }

    func bootstrap() async throws {
        if let bootstrapError { throw bootstrapError }
    }

    func fetchRooms() async throws -> [Room] { initialRooms }

    func create(room: Room) async throws { pushedRooms.append(room) }

    func push(room: Room) async throws { pushedRooms.append(room) }

    func pushClaim(room: Room, billID: UUID, itemID: UUID) async throws {
        pushedClaims.append((room.id, billID, itemID))
        if let conflict = nextClaimConflict {
            nextClaimConflict = nil
            throw SyncError.conflict(conflict)
        }
    }

    func shareURL(roomID: UUID) async throws -> URL {
        URL(string: "https://www.icloud.com/share/fake")!
    }

    func acceptShare(metadata: ShareMetadata) async throws {}

    func fetchRemoteChanges() async -> Bool { false }
}

@MainActor
@Suite("CloudKitRoomStore (fake sync)")
struct CloudKitRoomStoreTests {

    /// Builds a claiming-state room with one unclaimed item, plus IDs.
    private func fixture() -> (room: Room, hostID: UUID, ditaID: UUID, billID: UUID, itemID: UUID) {
        let host = Member(displayName: "Hosty", avatarEmoji: "🧑‍🍳", isHost: true)
        let dita = Member(displayName: "Dita", avatarEmoji: "🐱")
        var room = Room(name: "Warung Run", host: host)
        try! room.join(dita)
        let item = BillItem(name: "Gurame", unitPrice: 85_000)
        let bill = Bill(merchantName: "Warung", items: [item])
        try! room.addBill(bill, by: host.id)
        try! room.advance(by: host.id)
        return (room, host.id, dita.id, bill.id, item.id)
    }

    @Test("Intents apply optimistically and persist through the sync service")
    func optimisticApplyAndPush() async throws {
        let (room, hostID, _, billID, itemID) = fixture()
        let fake = FakeSyncService()
        fake.initialRooms = [room]
        let store = CloudKitRoomStore(sync: fake)
        // Let start() bootstrap + fetch.
        try await Task.sleep(for: .milliseconds(50))
        #expect(store.rooms.count == 1)

        store.setActingMember(hostID, in: room.id)
        store.claim(itemID: itemID, billID: billID, roomID: room.id)
        // Optimistic: local state updated immediately.
        #expect(store.room(withID: room.id)?
            .bill(withID: billID)?.item(withID: itemID)?.claimState.claimerIDs == [hostID])

        await store.waitForPushes()
        #expect(fake.pushedClaims.count == 1)
        #expect(fake.pushedClaims.first?.itemID == itemID)
        #expect(store.alert == nil)
    }

    /// The Milestone 4 conflict path: a remote member won the claim race
    /// (serverRecordChanged under the hood). The store must reconcile local
    /// state to the server room and alert "Already claimed by <names>".
    @Test("Lost claim race surfaces as 'Already claimed by <names>' and reconciles")
    func conflictReconciliation() async throws {
        let (room, hostID, ditaID, billID, itemID) = fixture()
        let fake = FakeSyncService()
        fake.initialRooms = [room]

        // Server truth: Dita already claimed the item.
        var serverRoom = room
        try serverRoom.claim(itemID: itemID, in: billID, as: ditaID)
        fake.nextClaimConflict = SyncConflict(
            itemID: itemID,
            claimerIDs: [ditaID],
            serverRoom: serverRoom
        )

        let store = CloudKitRoomStore(sync: fake)
        try await Task.sleep(for: .milliseconds(50))

        // Host claims locally — succeeds optimistically, then loses the race.
        store.setActingMember(hostID, in: room.id)
        store.claim(itemID: itemID, billID: billID, roomID: room.id)
        #expect(store.room(withID: room.id)?
            .bill(withID: billID)?.item(withID: itemID)?.claimState.claimerIDs == [hostID])

        await store.waitForPushes()

        // Exactly the same copy as the mock store's local conflict path.
        #expect(store.alert?.message == "Already claimed by Dita.")
        // Local state reconciled to the authoritative server record.
        #expect(store.room(withID: room.id)?
            .bill(withID: billID)?.item(withID: itemID)?.claimState.claimerIDs == [ditaID])
    }

    @Test("Remote snapshots from the update stream replace local state")
    func remoteUpdatesApply() async throws {
        let (room, _, ditaID, billID, itemID) = fixture()
        let fake = FakeSyncService()
        fake.initialRooms = [room]
        let store = CloudKitRoomStore(sync: fake)
        try await Task.sleep(for: .milliseconds(50))

        // Member B claims on their device; a push-driven fetch emits it.
        var serverRoom = room
        try serverRoom.claim(itemID: itemID, in: billID, as: ditaID)
        fake.emit(.rooms([serverRoom]))
        try await Task.sleep(for: .milliseconds(50))

        #expect(store.room(withID: room.id)?
            .bill(withID: billID)?.item(withID: itemID)?.claimState.claimerIDs == [ditaID])
    }

    @Test("No iCloud account surfaces a sign-in alert, not a crash")
    func notSignedIn() async throws {
        let fake = FakeSyncService()
        fake.bootstrapError = SyncError.notSignedIn
        let store = CloudKitRoomStore(sync: fake)
        try await Task.sleep(for: .milliseconds(50))
        #expect(store.alert?.message.contains("Sign in to iCloud") == true)
    }
}
