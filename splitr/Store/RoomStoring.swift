import Foundation
import Observation
import SplitBillCore

/// A user-facing error surfaced by the store, rendered as an alert.
struct StoreAlert: Identifiable, Equatable {
    let id = UUID()
    let message: String
}

/// Abstraction over room persistence and intents. Views only ever talk to
/// this protocol; Milestone 4 swaps the in-memory implementation for a
/// CloudKit-backed one without touching any view.
///
/// Intent methods never throw: failures from Core surface as `alert`.
/// The acting member (see the debug switcher) is the implicit actor for
/// every intent, so host-only rules are enforced by Core, not the UI.
@MainActor
protocol RoomStoring: AnyObject, Observable {
    var rooms: [Room] { get }
    var alert: StoreAlert? { get set }
    /// True while the initial room fetch is still in flight — the UI shows
    /// a loading state instead of a misleading "no rooms" empty state.
    var isLoadingRooms: Bool { get }

    func room(withID id: UUID) -> Room?

    /// The member whose perspective the UI currently acts from (defaults to host).
    func actingMemberID(in roomID: UUID) -> UUID?
    func setActingMember(_ memberID: UUID, in roomID: UUID)

    @discardableResult
    func createRoom(named name: String, hostName: String, hostEmoji: String) -> Room
    func joinMember(named name: String, emoji: String, roomID: UUID)
    /// Adds the current device as a member after opening an invite link and
    /// makes that member the active perspective for the room.
    func joinFromInvite(named name: String, emoji: String, roomID: UUID)
    func renameRoom(roomID: UUID, to newName: String)

    func advance(roomID: UUID)
    func rollbackToClaiming(roomID: UUID)
    func kick(memberID: UUID, roomID: UUID)

    func addBill(_ bill: Bill, roomID: UUID)
    /// Host-only; allowed only while the room is `.open`.
    func updateBill(_ bill: Bill, roomID: UUID)
    /// Host-only; allowed only while the room is `.open`.
    func removeBill(billID: UUID, roomID: UUID)

    func claim(itemID: UUID, billID: UUID, roomID: UUID)
    func joinClaim(itemID: UUID, billID: UUID, roomID: UUID)
    func releaseClaim(itemID: UUID, billID: UUID, roomID: UUID)
    func forceAssign(itemID: UUID, billID: UUID, to memberID: UUID, roomID: UUID)
    func toggleClaim(itemID: UUID, billID: UUID, for memberID: UUID, roomID: UUID)

    func markPaid(roomID: UUID)
    func confirmPayment(of memberID: UUID, roomID: UUID)

    func inviteURL(roomID: UUID) async -> URL?
    func addMember(_ member: Member, roomID: UUID)
    func acceptShare(from url: URL) async -> Bool
    func waitForRoom(id: UUID) async -> Bool
    func deleteRoom(roomID: UUID)
    func resetAllData()
}

extension RoomStoring {
    func resetAllData() {}
    func deleteRoom(roomID: UUID) {}
}
