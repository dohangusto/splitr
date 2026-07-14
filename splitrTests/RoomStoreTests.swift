import Foundation
import Testing
import SplitBillCore
@testable import splitr

/// Store-level tests replacing the removed XCUITest happy path (CLAUDE.md:
/// no UI automation). Intent methods are called directly — no simulator UI.
@MainActor
@Suite("RoomStore")
struct RoomStoreTests {

    private func makeItems() -> [BillItem] {
        [
            BillItem(name: "Nasi Goreng", unitPrice: 90_000),
            BillItem(name: "Nasi Goreng", unitPrice: 90_000),
        ]
    }

    /// The full Milestone 2 happy path, exercised through store intents:
    /// create → join → addBill → claim → shared join → settle →
    /// markPaid → confirm → close. `alert` must stay nil throughout.
    @Test("Happy path end to end through intents")
    func happyPath() throws {
        let store = MockRoomStore()
        let room = store.createRoom(named: "UITest Dinner", hostName: "Hosty", hostEmoji: "🧑‍🍳")
        let hostID = room.hostMemberID

        store.joinMember(named: "Guest", emoji: "🙂", roomID: room.id)
        let guestID = try #require(
            store.room(withID: room.id)?.members.first(where: { !$0.isHost })?.id
        )

        let items = makeItems()
        let bill = Bill(
            merchantName: "Test Warung",
            taxRate: .percent(10),
            serviceChargeRate: .percent(5),
            items: items
        )
        store.addBill(bill, roomID: room.id)
        #expect(store.room(withID: room.id)?.bills.count == 1)

        store.advance(roomID: room.id) // host → claiming
        #expect(store.room(withID: room.id)?.state == .claiming)

        // Host claims unit 1; guest joins the split and claims unit 2.
        store.claim(itemID: items[0].id, billID: bill.id, roomID: room.id)
        store.setActingMember(guestID, in: room.id)
        store.joinClaim(itemID: items[0].id, billID: bill.id, roomID: room.id)
        store.claim(itemID: items[1].id, billID: bill.id, roomID: room.id)

        let shared = store.room(withID: room.id)?
            .bill(withID: bill.id)?.item(withID: items[0].id)
        #expect(shared?.claimState.claimerIDs == [hostID, guestID])

        // Host closes claiming.
        store.setActingMember(hostID, in: room.id)
        store.advance(roomID: room.id)
        #expect(store.room(withID: room.id)?.state == .settling)

        // Settlement math is available and reconciles.
        let settlement = try SettlementCalculator.settle(room: store.room(withID: room.id)!)
        #expect(settlement.grandTotal
            == settlement.memberSettlements.reduce(0) { $0 + $1.totalOwed })

        // Guest marks paid; host confirms; host closes.
        store.setActingMember(guestID, in: room.id)
        store.markPaid(roomID: room.id)
        #expect(store.room(withID: room.id)?.member(withID: guestID)?.paymentStatus == .memberMarkedPaid)

        store.setActingMember(hostID, in: room.id)
        store.confirmPayment(of: guestID, roomID: room.id)
        #expect(store.room(withID: room.id)?.member(withID: guestID)?.paymentStatus == .hostConfirmed)

        store.advance(roomID: room.id)
        #expect(store.room(withID: room.id)?.state == .closed)
        #expect(store.alert == nil, "happy path must not surface any alert")
    }

    @Test("Double-claim surfaces 'Already claimed by <names>' instead of crashing")
    func doubleClaimAlert() throws {
        let store = MockRoomStore()
        let room = store.createRoom(named: "Conflict", hostName: "Hosty", hostEmoji: "🧑‍🍳")
        store.joinMember(named: "Dita", emoji: "🐱", roomID: room.id)
        store.joinMember(named: "Raka", emoji: "🦖", roomID: room.id)
        let dita = store.room(withID: room.id)!.members[1].id
        let raka = store.room(withID: room.id)!.members[2].id

        let item = BillItem(name: "Gurame", unitPrice: 85_000)
        let bill = Bill(merchantName: "Warung", items: [item])
        store.addBill(bill, roomID: room.id)
        store.advance(roomID: room.id)

        store.setActingMember(dita, in: room.id)
        store.claim(itemID: item.id, billID: bill.id, roomID: room.id)
        #expect(store.alert == nil)

        store.setActingMember(raka, in: room.id)
        store.claim(itemID: item.id, billID: bill.id, roomID: room.id)
        #expect(store.alert?.message == "Already claimed by Dita.")

        // The original claim survived the conflict.
        let state = store.room(withID: room.id)?.bill(withID: bill.id)?.item(withID: item.id)?.claimState
        #expect(state?.claimerIDs == [dita])
    }

    @Test("Shared-claim conflict names every holder")
    func sharedConflictNamesAll() throws {
        let store = MockRoomStore()
        let room = store.createRoom(named: "Conflict", hostName: "Hosty", hostEmoji: "🧑‍🍳")
        store.joinMember(named: "Dita", emoji: "🐱", roomID: room.id)
        store.joinMember(named: "Raka", emoji: "🦖", roomID: room.id)
        let dita = store.room(withID: room.id)!.members[1].id

        let item = BillItem(name: "Kentang", unitPrice: 25_000)
        let bill = Bill(merchantName: "Warung", items: [item])
        store.addBill(bill, roomID: room.id)
        store.advance(roomID: room.id)

        // Host claims, Dita joins → shared. Raka's fresh claim then conflicts.
        store.claim(itemID: item.id, billID: bill.id, roomID: room.id)
        store.setActingMember(dita, in: room.id)
        store.joinClaim(itemID: item.id, billID: bill.id, roomID: room.id)

        store.setActingMember(store.room(withID: room.id)!.members[2].id, in: room.id)
        store.claim(itemID: item.id, billID: bill.id, roomID: room.id)
        #expect(store.alert?.message == "Already claimed by Hosty, Dita.")
    }

    @Test("Non-host actions surface a host-only alert, not a crash")
    func hostOnlyAlert() throws {
        let store = MockRoomStore()
        let room = store.createRoom(named: "Rules", hostName: "Hosty", hostEmoji: "🧑‍🍳")
        store.joinMember(named: "Dita", emoji: "🐱", roomID: room.id)
        let dita = store.room(withID: room.id)!.members[1].id

        store.setActingMember(dita, in: room.id)
        store.advance(roomID: room.id)
        #expect(store.alert?.message == "Only the host can do that.")
        #expect(store.room(withID: room.id)?.state == .open)
    }

    /// Regression: `RoomStore.mutate` used to pass `&rooms[index]` inout while
    /// the intent closure re-read `rooms` to resolve the acting member —
    /// a Swift exclusivity violation that aborted the process (SIGABRT in
    /// swift_beginAccess). The actor is now resolved before the inout access.
    /// This test crashes, not fails, if that regresses.
    @Test("Exclusivity regression: intents resolve the acting member during mutation")
    func exclusivityRegression() throws {
        let store = MockRoomStore()
        let room = store.createRoom(named: "Exclusivity", hostName: "Hosty", hostEmoji: "🧑‍🍳")
        store.joinMember(named: "Dita", emoji: "🐱", roomID: room.id)
        let dita = store.room(withID: room.id)!.members[1].id

        // Non-default acting member forces actingMemberID(in:) down the
        // dictionary + rooms-lookup path that overlapped the inout access.
        store.setActingMember(dita, in: room.id)
        store.setActingMember(room.hostMemberID, in: room.id)

        let item = BillItem(name: "Sate", unitPrice: 35_000)
        let bill = Bill(merchantName: "Warung", items: [item])
        store.addBill(bill, roomID: room.id) // ← crashed here before the fix
        store.advance(roomID: room.id)
        store.setActingMember(dita, in: room.id)
        store.claim(itemID: item.id, billID: bill.id, roomID: room.id)

        #expect(store.alert == nil)
        #expect(store.room(withID: room.id)?.bills.count == 1)
    }

    @Test("Intents on a nonexistent room are ignored, not crashes")
    func unknownRoomIsNoop() throws {
        let store = MockRoomStore()
        store.advance(roomID: UUID())
        store.markPaid(roomID: UUID())
        #expect(store.alert == nil)
        #expect(store.rooms.isEmpty)
    }
}
