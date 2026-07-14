import Foundation
import Observation
import SplitBillCore

/// In-memory implementation of `RoomStoring` — used by unit tests, SwiftUI
/// previews, and the simulator (no iCloud account needed).
/// Owns plain `Room` values and funnels every mutation through Core's
/// throwing API; Core errors become `alert` messages.
@Observable
final class MockRoomStore: RoomStoring {
    private(set) var rooms: [Room]
    var alert: StoreAlert?

    /// Per-room "acting as" member for the debug perspective switcher.
    private var actingByRoom: [UUID: UUID] = [:]

    init(rooms: [Room] = []) {
        self.rooms = rooms
    }

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
        return room
    }

    func joinMember(named name: String, emoji: String, roomID: UUID) {
        mutate(roomID) { room, _ in
            try room.join(Member(displayName: name, avatarEmoji: emoji))
        }
    }

    func advance(roomID: UUID) {
        mutate(roomID) { room, actor in
            try room.advance(by: actor)
        }
    }

    func rollbackToClaiming(roomID: UUID) {
        mutate(roomID) { room, actor in
            try room.rollbackToClaiming(by: actor)
        }
    }

    func kick(memberID: UUID, roomID: UUID) {
        mutate(roomID) { room, actor in
            try room.kick(memberID: memberID, by: actor)
        }
    }

    func addBill(_ bill: Bill, roomID: UUID) {
        mutate(roomID) { room, actor in
            try room.addBill(bill, by: actor)
        }
    }

    func claim(itemID: UUID, billID: UUID, roomID: UUID) {
        mutate(roomID) { room, actor in
            try room.claim(itemID: itemID, in: billID, as: actor)
        }
    }

    func joinClaim(itemID: UUID, billID: UUID, roomID: UUID) {
        mutate(roomID) { room, actor in
            try room.joinClaim(itemID: itemID, in: billID, as: actor)
        }
    }

    func releaseClaim(itemID: UUID, billID: UUID, roomID: UUID) {
        mutate(roomID) { room, actor in
            try room.releaseClaim(itemID: itemID, in: billID, as: actor)
        }
    }

    func forceAssign(itemID: UUID, billID: UUID, to memberID: UUID, roomID: UUID) {
        mutate(roomID) { room, actor in
            try room.forceAssign(itemID: itemID, in: billID, to: memberID, by: actor)
        }
    }

    func markPaid(roomID: UUID) {
        mutate(roomID) { room, actor in
            try room.markPaid(as: actor)
        }
    }

    func confirmPayment(of memberID: UUID, roomID: UUID) {
        mutate(roomID) { room, actor in
            try room.confirmPayment(of: memberID, by: actor)
        }
    }

    // MARK: - Private

    /// Resolves the acting member, then hands the room to `body` inout.
    /// The actor must be resolved *before* `&rooms[index]` is exclusively
    /// accessed — reading `rooms` inside `body` violates exclusivity.
    private func mutate(_ roomID: UUID, _ body: (inout Room, _ actor: UUID) throws -> Void) {
        guard let index = rooms.firstIndex(where: { $0.id == roomID }) else { return }
        let actor = actingMemberID(in: roomID) ?? rooms[index].hostMemberID
        do {
            try body(&rooms[index], actor)
        } catch {
            alert = StoreAlert(message: StoreCopy.message(for: error, in: rooms[index]))
        }
    }

}
