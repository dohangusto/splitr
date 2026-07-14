import Foundation
import Testing
@testable import SplitBillCore

@Suite("Room state machine")
struct RoomStateMachineTests {
    let host = Fixtures.host()
    let alice = Fixtures.member("Alice", emoji: "🦊")
    let bob = Fixtures.member("Bob", emoji: "🐼")

    @Test("Host advances through the full lifecycle")
    func fullLifecycle() throws {
        var room = try Fixtures.openRoom(host: host)
        #expect(room.state == .open)
        try room.advance(by: host.id)
        #expect(room.state == .claiming)
        try room.advance(by: host.id)
        #expect(room.state == .settling)
        try room.advance(by: host.id)
        #expect(room.state == .closed)
    }

    @Test("Closed is terminal — advancing throws")
    func closedIsTerminal() throws {
        var room = try Fixtures.openRoom(host: host)
        try room.advance(by: host.id)
        try room.advance(by: host.id)
        try room.advance(by: host.id)
        #expect(throws: RoomError.roomIsClosed) {
            try room.advance(by: host.id)
        }
        #expect(room.state == .closed)
    }

    @Test("Non-host cannot advance")
    func nonHostCannotAdvance() throws {
        var room = try Fixtures.openRoom(host: host, members: [alice])
        #expect(throws: RoomError.notHost(alice.id)) {
            try room.advance(by: alice.id)
        }
        #expect(room.state == .open)
    }

    @Test("Settling rolls back to claiming")
    func rollbackFromSettling() throws {
        var room = try Fixtures.openRoom(host: host)
        try room.advance(by: host.id)
        try room.advance(by: host.id)
        #expect(room.state == .settling)
        try room.rollbackToClaiming(by: host.id)
        #expect(room.state == .claiming)
    }

    @Test("Rollback is illegal from open, claiming, and closed",
          arguments: [RoomState.open, .claiming, .closed])
    func rollbackIllegalElsewhere(target: RoomState) throws {
        var room = try Fixtures.openRoom(host: host)
        while room.state != target {
            try room.advance(by: host.id)
        }
        #expect(throws: RoomError.invalidTransition(from: target, to: .claiming)) {
            try room.rollbackToClaiming(by: host.id)
        }
        #expect(room.state == target)
    }

    @Test("Non-host cannot roll back")
    func nonHostCannotRollBack() throws {
        var room = try Fixtures.openRoom(host: host, members: [alice])
        try room.advance(by: host.id)
        try room.advance(by: host.id)
        #expect(throws: RoomError.notHost(alice.id)) {
            try room.rollbackToClaiming(by: alice.id)
        }
    }

    @Test("Members can join during open and claiming, not later")
    func joinWindows() throws {
        var room = try Fixtures.openRoom(host: host)
        try room.join(alice)
        try room.advance(by: host.id)
        try room.join(bob) // late joiner during claiming is allowed
        #expect(room.members.count == 3)

        try room.advance(by: host.id)
        #expect(throws: RoomError.joiningNotAllowed(.settling)) {
            try room.join(Fixtures.member("Cara"))
        }
        try room.advance(by: host.id)
        #expect(throws: RoomError.joiningNotAllowed(.closed)) {
            try room.join(Fixtures.member("Dodi"))
        }
    }

    @Test("Duplicate join throws")
    func duplicateJoin() throws {
        var room = try Fixtures.openRoom(host: host, members: [alice])
        #expect(throws: RoomError.memberAlreadyJoined(alice.id)) {
            try room.join(alice)
        }
    }

    @Test("Joiners are never host and start unpaid")
    func joinNormalizesFlags() throws {
        var room = try Fixtures.openRoom(host: host)
        var impostor = Fixtures.member("Impostor")
        impostor.isHost = true
        impostor.paymentStatus = .hostConfirmed
        try room.join(impostor)
        let joined = try #require(room.member(withID: impostor.id))
        #expect(!joined.isHost)
        #expect(joined.paymentStatus == .none)
    }

    @Test("Kick removes the member and unclaims everything they held")
    func kickUnclaims() throws {
        let solo = BillItem(name: "Nasi Goreng", unitPrice: 55_000)
        let shared = BillItem(name: "Kentang Goreng", unitPrice: 25_000)
        let assigned = BillItem(name: "Es Teh", unitPrice: 10_000)
        let untouched = BillItem(name: "Sate", unitPrice: 62_000)
        let bill = Bill(merchantName: "Warung", items: [solo, shared, assigned, untouched])
        var room = try Fixtures.claimingRoom(host: host, members: [alice, bob], bill: bill)

        try room.claim(itemID: solo.id, in: bill.id, as: alice.id)
        try room.claimShared(itemID: shared.id, in: bill.id, among: [alice.id, bob.id])
        try room.forceAssign(itemID: assigned.id, in: bill.id, to: alice.id, by: host.id)
        try room.claim(itemID: untouched.id, in: bill.id, as: bob.id)

        try room.kick(memberID: alice.id, by: host.id)

        #expect(room.member(withID: alice.id) == nil)
        let items = try #require(room.bill(withID: bill.id)).items
        #expect(items[0].claimState == .unclaimed) // solo claim gone
        #expect(items[1].claimState == .unclaimed) // shared claim fully reset
        #expect(items[2].claimState == .unclaimed) // force-assignment gone
        // Bob's own claim is untouched.
        #expect(items[3].claimState.claimerIDs == [bob.id])
    }

    @Test("Only the host can kick, and never themselves")
    func kickRules() throws {
        var room = try Fixtures.openRoom(host: host, members: [alice, bob])
        #expect(throws: RoomError.notHost(alice.id)) {
            try room.kick(memberID: bob.id, by: alice.id)
        }
        #expect(throws: RoomError.cannotKickHost) {
            try room.kick(memberID: host.id, by: host.id)
        }
        let ghost = UUID()
        let snapshot = room
        #expect(throws: RoomError.memberNotFound(ghost)) {
            var copy = snapshot
            try copy.kick(memberID: ghost, by: host.id)
        }
    }

    @Test("Bills can only be added by the host before settling")
    func addBillRules() throws {
        var room = try Fixtures.openRoom(host: host, members: [alice])
        let bill = Bill(merchantName: "Warung")
        #expect(throws: RoomError.notHost(alice.id)) {
            try room.addBill(bill, by: alice.id)
        }
        try room.addBill(bill, by: host.id)
        #expect(throws: RoomError.billAlreadyAdded(bill.id)) {
            try room.addBill(bill, by: host.id)
        }
        try room.advance(by: host.id)
        try room.advance(by: host.id)
        #expect(throws: RoomError.billEditingNotAllowed(.settling)) {
            try room.addBill(Bill(merchantName: "Kafe"), by: host.id)
        }
    }

    @Test("Payment tracking runs during settling only, host confirms")
    func paymentFlow() throws {
        var room = try Fixtures.openRoom(host: host, members: [alice])

        #expect(throws: RoomError.paymentUpdateNotAllowed(.open)) {
            try room.markPaid(as: alice.id)
        }

        try room.advance(by: host.id)
        try room.advance(by: host.id)
        try room.markPaid(as: alice.id)
        #expect(room.member(withID: alice.id)?.paymentStatus == .memberMarkedPaid)

        #expect(throws: RoomError.notHost(alice.id)) {
            try room.confirmPayment(of: alice.id, by: alice.id)
        }
        try room.confirmPayment(of: alice.id, by: host.id)
        #expect(room.member(withID: alice.id)?.paymentStatus == .hostConfirmed)

        #expect(throws: RoomError.hostHasNoPayment) {
            try room.markPaid(as: host.id)
        }
    }
}
