import Foundation
import Testing
@testable import SplitBillCore

@Suite("Claiming")
struct ClaimingTests {
    let host = Fixtures.host()
    let alice = Fixtures.member("Alice", emoji: "🦊")
    let bob = Fixtures.member("Bob", emoji: "🐼")
    let cara = Fixtures.member("Cara", emoji: "🐸")

    let item = BillItem(name: "Kentang Goreng", unitPrice: 25_000)
    let bill: Bill

    init() {
        bill = Bill(merchantName: "Warung", items: [item])
    }

    private func makeRoom() throws -> Room {
        try Fixtures.claimingRoom(host: host, members: [alice, bob, cara], bill: bill)
    }

    @Test("Single member claims a whole item")
    func singleClaim() throws {
        var room = try makeRoom()
        try room.claim(itemID: item.id, in: bill.id, as: alice.id)
        let claimed = try #require(room.bill(withID: bill.id)?.item(withID: item.id))
        #expect(claimed.claimState == .claimed([
            Claim(itemID: item.id, memberID: alice.id, portion: .one)
        ]))
    }

    @Test("Shared claim defaults to an equal split summing to exactly 1")
    func sharedClaimEqualSplit() throws {
        var room = try makeRoom()
        try room.claimShared(itemID: item.id, in: bill.id, among: [alice.id, bob.id, cara.id])
        let claimed = try #require(room.bill(withID: bill.id)?.item(withID: item.id))
        guard case .claimed(let claims) = claimed.claimState else {
            Issue.record("Expected claimed state")
            return
        }
        #expect(claims.count == 3)
        #expect(claims.allSatisfy { $0.portion == Fraction(1, 3) })
        #expect(claims.reduce(Fraction.zero) { $0 + $1.portion } == .one)
    }

    @Test("Explicit uneven portions summing to 1 are accepted")
    func unevenPortions() throws {
        var room = try makeRoom()
        try room.claim(itemID: item.id, in: bill.id, portions: [
            (alice.id, Fraction(1, 2)),
            (bob.id, Fraction(1, 4)),
            (cara.id, Fraction(1, 4)),
        ])
        let claimed = try #require(room.bill(withID: bill.id)?.item(withID: item.id))
        #expect(claimed.claimState.claimerIDs.count == 3)
    }

    @Test("Portions that do not sum to 1 are rejected")
    func portionsMustSumToOne() throws {
        let room = try makeRoom()
        #expect(throws: ClaimError.portionsMustSumToOne(actual: Fraction(3, 4))) {
            var copy = room
            try copy.claim(itemID: item.id, in: bill.id, portions: [
                (alice.id, Fraction(1, 2)),
                (bob.id, Fraction(1, 4)),
            ])
        }
    }

    @Test("Zero and negative portions are rejected")
    func nonPositivePortions() throws {
        let room = try makeRoom()
        #expect(throws: ClaimError.nonPositivePortion) {
            var copy = room
            try copy.claim(itemID: item.id, in: bill.id, portions: [
                (alice.id, Fraction(0)),
                (bob.id, .one),
            ])
        }
    }

    @Test("Empty and duplicate claimer lists are rejected")
    func degenerateClaimerLists() throws {
        let room = try makeRoom()
        #expect(throws: ClaimError.noClaimers) {
            var copy = room
            try copy.claim(itemID: item.id, in: bill.id, portions: [])
        }
        #expect(throws: ClaimError.duplicateClaimers) {
            var copy = room
            try copy.claim(itemID: item.id, in: bill.id, portions: [
                (alice.id, Fraction(1, 2)),
                (alice.id, Fraction(1, 2)),
            ])
        }
    }

    @Test("Claiming an already-claimed item names the current holders")
    func doubleClaimConflict() throws {
        var room = try makeRoom()
        try room.claimShared(itemID: item.id, in: bill.id, among: [alice.id, bob.id])
        let snapshot = room
        #expect(throws: ClaimError.alreadyClaimed(itemID: item.id, claimers: [alice.id, bob.id])) {
            var copy = snapshot
            try copy.claim(itemID: item.id, in: bill.id, as: cara.id)
        }
        // The original claim is untouched by the failed attempt.
        #expect(room.bill(withID: bill.id)?.item(withID: item.id)?.claimState.claimerIDs == [alice.id, bob.id])
    }

    @Test("Claiming a force-assigned item is a conflict too")
    func claimForceAssignedConflict() throws {
        var room = try makeRoom()
        try room.forceAssign(itemID: item.id, in: bill.id, to: bob.id, by: host.id)
        let snapshot = room
        #expect(throws: ClaimError.alreadyClaimed(itemID: item.id, claimers: [bob.id])) {
            var copy = snapshot
            try copy.claim(itemID: item.id, in: bill.id, as: alice.id)
        }
    }

    @Test("Host force-assign overrides an existing claim")
    func forceAssignOverrides() throws {
        var room = try makeRoom()
        try room.claimShared(itemID: item.id, in: bill.id, among: [alice.id, bob.id])
        try room.forceAssign(itemID: item.id, in: bill.id, to: cara.id, by: host.id)
        let state = try #require(room.bill(withID: bill.id)?.item(withID: item.id)?.claimState)
        #expect(state == .forceAssigned(cara.id))
    }

    @Test("Only the host may force-assign")
    func forceAssignHostOnly() throws {
        let room = try makeRoom()
        #expect(throws: RoomError.notHost(alice.id)) {
            var copy = room
            try copy.forceAssign(itemID: item.id, in: bill.id, to: alice.id, by: alice.id)
        }
    }

    @Test("Joining a claim re-splits equally among all claimers")
    func joinClaim() throws {
        var room = try makeRoom()
        try room.claim(itemID: item.id, in: bill.id, as: alice.id)
        try room.joinClaim(itemID: item.id, in: bill.id, as: bob.id)
        try room.joinClaim(itemID: item.id, in: bill.id, as: cara.id)
        let state = try #require(room.bill(withID: bill.id)?.item(withID: item.id)?.claimState)
        guard case .claimed(let claims) = state else {
            Issue.record("Expected claimed state")
            return
        }
        #expect(claims.map(\.memberID) == [alice.id, bob.id, cara.id])
        #expect(claims.allSatisfy { $0.portion == Fraction(1, 3) })
    }

    @Test("Joining an unclaimed item claims it whole; joining twice or joining a force-assignment fails")
    func joinClaimEdges() throws {
        var room = try makeRoom()
        try room.joinClaim(itemID: item.id, in: bill.id, as: alice.id)
        #expect(room.bill(withID: bill.id)?.item(withID: item.id)?.claimState
            == .claimed([Claim(itemID: item.id, memberID: alice.id, portion: .one)]))

        let claimed = room
        #expect(throws: ClaimError.alreadyAClaimer(itemID: item.id, memberID: alice.id)) {
            var copy = claimed
            try copy.joinClaim(itemID: item.id, in: bill.id, as: alice.id)
        }

        try room.forceAssign(itemID: item.id, in: bill.id, to: bob.id, by: host.id)
        let assigned = room
        #expect(throws: ClaimError.alreadyClaimed(itemID: item.id, claimers: [bob.id])) {
            var copy = assigned
            try copy.joinClaim(itemID: item.id, in: bill.id, as: cara.id)
        }
    }

    @Test("A claimer can release their claim; the item returns to unclaimed")
    func releaseClaim() throws {
        var room = try makeRoom()
        try room.claimShared(itemID: item.id, in: bill.id, among: [alice.id, bob.id])
        try room.releaseClaim(itemID: item.id, in: bill.id, as: alice.id)
        #expect(room.bill(withID: bill.id)?.item(withID: item.id)?.claimState == .unclaimed)
    }

    @Test("Non-claimers cannot release, and force-assignments are host-owned")
    func releaseClaimRules() throws {
        var room = try makeRoom()
        try room.claim(itemID: item.id, in: bill.id, as: alice.id)
        let claimed = room
        #expect(throws: ClaimError.notAClaimer(itemID: item.id, memberID: bob.id)) {
            var copy = claimed
            try copy.releaseClaim(itemID: item.id, in: bill.id, as: bob.id)
        }
        try room.forceAssign(itemID: item.id, in: bill.id, to: bob.id, by: host.id)
        let assigned = room
        #expect(throws: ClaimError.notAClaimer(itemID: item.id, memberID: bob.id)) {
            var copy = assigned
            try copy.releaseClaim(itemID: item.id, in: bill.id, as: bob.id)
        }
    }

    @Test("Claims are only accepted while the room is claiming")
    func claimWindow() throws {
        let openHost = Fixtures.host()
        var room = try Fixtures.openRoom(host: openHost, members: [alice])
        let bill = Bill(merchantName: "Warung", items: [item])
        try room.addBill(bill, by: openHost.id)

        let openSnapshot = room
        #expect(throws: ClaimError.claimingNotAllowed(.open)) {
            var copy = openSnapshot
            try copy.claim(itemID: item.id, in: bill.id, as: alice.id)
        }

        try room.advance(by: openHost.id)
        try room.advance(by: openHost.id)
        let settlingSnapshot = room
        #expect(throws: ClaimError.claimingNotAllowed(.settling)) {
            var copy = settlingSnapshot
            try copy.claim(itemID: item.id, in: bill.id, as: alice.id)
        }
    }

    @Test("Claims validate member, bill, and item existence")
    func claimTargetValidation() throws {
        let room = try makeRoom()
        let ghost = UUID()
        #expect(throws: ClaimError.memberNotFound(ghost)) {
            var copy = room
            try copy.claim(itemID: item.id, in: bill.id, as: ghost)
        }
        #expect(throws: ClaimError.billNotFound(ghost)) {
            var copy = room
            try copy.claim(itemID: item.id, in: ghost, as: alice.id)
        }
        #expect(throws: ClaimError.itemNotFound(ghost)) {
            var copy = room
            try copy.claim(itemID: ghost, in: bill.id, as: alice.id)
        }
    }

    @Test("Rollback from settling reopens claiming")
    func rollbackReopensClaiming() throws {
        var room = try makeRoom()
        try room.advance(by: host.id)
        #expect(room.state == .settling)
        try room.rollbackToClaiming(by: host.id)
        try room.claim(itemID: item.id, in: bill.id, as: alice.id)
        #expect(room.bill(withID: bill.id)?.item(withID: item.id)?.claimState.claimerIDs == [alice.id])
    }

    @Test("claims(for:) reports portions and force-assignments")
    func claimsQuery() throws {
        let second = BillItem(name: "Es Teh", unitPrice: 10_000)
        var bill = self.bill
        bill.items.append(second)
        var room = try Fixtures.claimingRoom(host: host, members: [alice, bob], bill: bill)
        try room.claimShared(itemID: item.id, in: bill.id, among: [alice.id, bob.id])
        try room.forceAssign(itemID: second.id, in: bill.id, to: alice.id, by: host.id)

        let aliceClaims = room.claims(for: alice.id)
        #expect(aliceClaims.count == 2)
        #expect(aliceClaims.first { $0.itemID == item.id }?.portion == Fraction(1, 2))
        #expect(aliceClaims.first { $0.itemID == second.id }?.portion == .one)
        #expect(room.claims(for: bob.id).count == 1)
    }
}
