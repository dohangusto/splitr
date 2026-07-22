import Foundation
import Testing
@testable import SplitBillCore

@Suite("Settlement math")
struct SettlementTests {
    let hostID = UUID()
    let bobID = UUID()
    let caraID = UUID()

    /// Golden-number test with a realistic Indonesian receipt.
    ///
    /// Warung receipt, subtotal Rp 187.000, PB1 10%, service 5%:
    ///   Nasi Goreng   55.000  → host
    ///   Sate          67.000  → Bob
    ///   Es Teh        10.000  → Cara
    ///   Kentang       25.000  → shared 3 ways (8.333⅓ each)
    ///   Gurame        30.000  → shared Bob + Cara (15.000 each)
    ///
    /// Exact subtotals: host 63.333⅓, Bob 90.333⅓, Cara 33.333⅓.
    /// Tax total = 18.700, service total = 9.350, grand total = 215.050.
    /// Non-hosts pay floors; host absorbs the remainder (4 rupiah here).
    /// The five golden-receipt items: host 63.333⅓, Bob 90.333⅓, Cara 33.333⅓ exact.
    private func goldenBill(tax: Int, serviceCharge: Int, discount: Int = 0) -> Bill {
        let nasi = BillItem(name: "Nasi Goreng", unitPrice: 55_000,
                            claimState: .claimed([Claim(itemID: UUID(), memberID: hostID, portion: .one)]))
        let sate = BillItem(name: "Sate", unitPrice: 67_000,
                            claimState: .claimed([Claim(itemID: UUID(), memberID: bobID, portion: .one)]))
        let esTeh = BillItem(name: "Es Teh", unitPrice: 10_000,
                             claimState: .claimed([Claim(itemID: UUID(), memberID: caraID, portion: .one)]))
        let kentangID = UUID()
        let kentang = BillItem(id: kentangID, name: "Kentang Goreng", unitPrice: 25_000,
                               claimState: .claimed([
                                   Claim(itemID: kentangID, memberID: hostID, portion: Fraction(1, 3)),
                                   Claim(itemID: kentangID, memberID: bobID, portion: Fraction(1, 3)),
                                   Claim(itemID: kentangID, memberID: caraID, portion: Fraction(1, 3)),
                               ]))
        let gurameID = UUID()
        let gurame = BillItem(id: gurameID, name: "Gurame Bakar", unitPrice: 30_000,
                              claimState: .claimed([
                                  Claim(itemID: gurameID, memberID: bobID, portion: Fraction(1, 2)),
                                  Claim(itemID: gurameID, memberID: caraID, portion: Fraction(1, 2)),
                              ]))
        return Bill(
            merchantName: "Warung Tekko",
            tax: tax,
            serviceCharge: serviceCharge,
            discount: discount,
            items: [nasi, sate, esTeh, kentang, gurame]
        )
    }

    @Test("Golden receipt: proportional tax/service to exact rupiah for every member")
    func goldenReceipt() throws {
        // Printed tax 18.700, service 9.350 (was 10% / 5% of the 187.000 subtotal).
        let bill = goldenBill(tax: 18_700, serviceCharge: 9_350)

        let settlement = try SettlementCalculator.settle(
            bill: bill,
            memberIDs: [hostID, bobID, caraID],
            hostMemberID: hostID
        )

        #expect(settlement.billSubtotal == 187_000)
        #expect(settlement.taxTotal == 18_700)
        #expect(settlement.serviceTotal == 9_350)
        #expect(settlement.grandTotal == 215_050)

        let bob = try #require(settlement.settlement(for: bobID))
        #expect(bob.subtotal == 90_333)
        #expect(bob.taxShare == 9_033)
        #expect(bob.serviceShare == 4_516)
        #expect(bob.totalOwed == 103_882)

        let cara = try #require(settlement.settlement(for: caraID))
        #expect(cara.subtotal == 33_333)
        #expect(cara.taxShare == 3_333)
        #expect(cara.serviceShare == 1_666)
        #expect(cara.totalOwed == 38_332)

        let host = try #require(settlement.settlement(for: hostID))
        #expect(host.subtotal == 63_334)
        #expect(host.taxShare == 6_334)
        #expect(host.serviceShare == 3_168)
        #expect(host.totalOwed == 72_836)

        // Members' totals reconcile exactly to the bill total.
        let sum = settlement.memberSettlements.reduce(0) { $0 + $1.totalOwed }
        #expect(sum == settlement.grandTotal)
        // Host absorbed 4 rupiah of rounding (1 subtotal + 1 tax + 2 service).
        #expect(settlement.roundingRemainder == 4)
    }

    /// Same receipt, but PB1 on subtotal + service (the common Indonesian
    /// format and the default): service = 9.350, tax base = 196.350,
    /// tax = 19.635, grand total = 215.985.
    @Test("Golden receipt with a larger tax total: exact rupiah for every member")
    func goldenReceiptLargerTax() throws {
        // Printed tax 19.635 (was PB1 on subtotal + service), service 9.350.
        let bill = goldenBill(tax: 19_635, serviceCharge: 9_350)

        let settlement = try SettlementCalculator.settle(
            bill: bill,
            memberIDs: [hostID, bobID, caraID],
            hostMemberID: hostID
        )

        #expect(settlement.billSubtotal == 187_000)
        #expect(settlement.serviceTotal == 9_350)
        #expect(settlement.taxTotal == 19_635)
        #expect(settlement.grandTotal == 215_985)

        // 19.635 / 187.000 = 35 / 561·1000, so each share is exact here:
        // Bob 90.333⅓ → 9.485, Cara 33.333⅓ → 3.500, host 63.333⅓ → 6.650.
        let bob = try #require(settlement.settlement(for: bobID))
        #expect(bob.subtotal == 90_333)
        #expect(bob.taxShare == 9_485)
        #expect(bob.serviceShare == 4_516)
        #expect(bob.totalOwed == 104_334)

        let cara = try #require(settlement.settlement(for: caraID))
        #expect(cara.subtotal == 33_333)
        #expect(cara.taxShare == 3_500)
        #expect(cara.serviceShare == 1_666)
        #expect(cara.totalOwed == 38_499)

        let host = try #require(settlement.settlement(for: hostID))
        #expect(host.subtotal == 63_334)
        #expect(host.taxShare == 6_650)
        #expect(host.serviceShare == 3_168)
        #expect(host.totalOwed == 73_152)

        let sum = settlement.memberSettlements.reduce(0) { $0 + $1.totalOwed }
        #expect(sum == settlement.grandTotal)
        // 1 rupiah subtotal + 0 tax (exact) + 2 service.
        #expect(settlement.roundingRemainder == 3)
    }

    @Test("Whole-item claims with exact thirds produce zero remainder")
    func exactSplitNoRemainder() throws {
        let items = [
            claimedItem(price: 60_000, by: hostID),
            claimedItem(price: 90_000, by: bobID),
            claimedItem(price: 30_000, by: caraID),
        ]
        let bill = Bill(merchantName: "Kafe", tax: 18_000, items: items)
        let settlement = try SettlementCalculator.settle(
            bill: bill, memberIDs: [hostID, bobID, caraID], hostMemberID: hostID
        )
        #expect(settlement.roundingRemainder == 0)
        #expect(settlement.settlement(for: bobID)?.totalOwed == 99_000)
        #expect(settlement.settlement(for: caraID)?.totalOwed == 33_000)
        #expect(settlement.settlement(for: hostID)?.totalOwed == 66_000)
    }

    @Test("Tax and service are proportional to subtotal, never per head")
    func proportionalNotPerHead() throws {
        // Bob claims 3x what Cara does; his tax share must be exactly 3x too.
        let items = [
            claimedItem(price: 150_000, by: bobID),
            claimedItem(price: 50_000, by: caraID),
        ]
        let bill = Bill(merchantName: "Kafe", tax: 20_000, items: items)
        let settlement = try SettlementCalculator.settle(
            bill: bill, memberIDs: [hostID, bobID, caraID], hostMemberID: hostID
        )
        let bob = try #require(settlement.settlement(for: bobID))
        let cara = try #require(settlement.settlement(for: caraID))
        #expect(bob.taxShare == 3 * cara.taxShare)
        // The host claimed nothing and absorbs nothing here (splits are exact).
        #expect(settlement.settlement(for: hostID)?.totalOwed == 0)
    }

    @Test("Unclaimed items block settlement")
    func unclaimedItemsBlock() throws {
        let stray = BillItem(name: "Kerupuk", unitPrice: 5_000)
        let bill = Bill(merchantName: "Warung", items: [claimedItem(price: 10_000, by: bobID), stray])
        #expect(throws: SettlementError.unclaimedItems([stray.id])) {
            _ = try SettlementCalculator.settle(
                bill: bill, memberIDs: [hostID, bobID], hostMemberID: hostID
            )
        }
    }

    @Test("Malformed portions are rejected")
    func invalidPortions() throws {
        let itemID = UUID()
        let bad = BillItem(id: itemID, name: "Sate", unitPrice: 40_000,
                           claimState: .claimed([
                               Claim(itemID: itemID, memberID: bobID, portion: Fraction(1, 2)),
                           ]))
        let bill = Bill(merchantName: "Warung", items: [bad])
        #expect(throws: SettlementError.invalidPortions(itemID: itemID)) {
            _ = try SettlementCalculator.settle(
                bill: bill, memberIDs: [hostID, bobID], hostMemberID: hostID
            )
        }
    }

    @Test("Claims by unknown members are rejected")
    func unknownClaimer() throws {
        let ghost = UUID()
        let item = claimedItem(price: 10_000, by: ghost)
        let bill = Bill(merchantName: "Warung", items: [item])
        #expect(throws: SettlementError.unknownClaimer(itemID: item.id, memberID: ghost)) {
            _ = try SettlementCalculator.settle(
                bill: bill, memberIDs: [hostID, bobID], hostMemberID: hostID
            )
        }
    }

    @Test("Host must be part of the settlement")
    func hostRequired() throws {
        let bill = Bill(merchantName: "Warung", items: [])
        #expect(throws: SettlementError.hostNotIncluded) {
            _ = try SettlementCalculator.settle(
                bill: bill, memberIDs: [bobID], hostMemberID: hostID
            )
        }
    }

    @Test("Empty bill settles to all zeroes")
    func emptyBill() throws {
        let bill = Bill(merchantName: "Warung")
        let settlement = try SettlementCalculator.settle(
            bill: bill, memberIDs: [hostID, bobID], hostMemberID: hostID
        )
        #expect(settlement.grandTotal == 0)
        #expect(settlement.memberSettlements.allSatisfy { $0.totalOwed == 0 })
    }

    @Test("Room-level settlement aggregates across bills")
    func roomAggregation() throws {
        let host = Fixtures.host()
        let alice = Fixtures.member("Alice")
        var room = try Fixtures.openRoom(host: host, members: [alice])

        let dinner = Bill(merchantName: "Warung", tax: 10_000,
                          items: [claimedItem(price: 100_000, by: alice.id)])
        let dessert = Bill(merchantName: "Kafe", tax: 5_000,
                           items: [claimedItem(price: 50_000, by: alice.id)])
        try room.addBill(dinner, by: host.id)
        try room.addBill(dessert, by: host.id)

        let settlement = try SettlementCalculator.settle(room: room)
        #expect(settlement.billSubtotal == 150_000)
        #expect(settlement.taxTotal == 15_000)
        #expect(settlement.grandTotal == 165_000)
        #expect(settlement.settlement(for: alice.id)?.totalOwed == 165_000)
        #expect(settlement.settlement(for: host.id)?.totalOwed == 0)
    }

    // MARK: - Per-bill remainder rule (settled product decision)

    /// Pins the decision that split remainders are absorbed **per bill**,
    /// never summed across bills and rounded once at room level. Each of
    /// two identical bills has one Rp 5.001 item split evenly between Bob
    /// and the host: Bob's exact share is 2.500,5 per bill.
    ///
    /// Per-bill rule → Bob pays floor(2.500,5) = 2.500 twice = 5.000, the
    /// host absorbs 1 rupiah in each bill (2 total). A room-level rounding
    /// would see Bob's exact 2.500,5 + 2.500,5 = 5.001 and absorb nothing —
    /// so 5.000 vs 5.001 is exactly the difference this test defends. Bills
    /// are independent; each reconciles alone like the paper it came from.
    /// Do not "improve" this to round once per room (see CLAUDE.md).
    @Test("Remainders are absorbed per bill, not once per room")
    func perBillRemainderAbsorption() throws {
        let host = Fixtures.host()
        let bob = Fixtures.member("Bob")
        var room = try Fixtures.openRoom(host: host, members: [bob])

        func halfAndHalfBill(_ name: String) -> Bill {
            let itemID = UUID()
            let item = BillItem(id: itemID, name: "Sate", unitPrice: 5_001,
                                claimState: .claimed([
                                    Claim(itemID: itemID, memberID: bob.id, portion: Fraction(1, 2)),
                                    Claim(itemID: itemID, memberID: host.id, portion: Fraction(1, 2)),
                                ]))
            return Bill(merchantName: name, items: [item])
        }
        try room.addBill(halfAndHalfBill("Warung"), by: host.id)
        try room.addBill(halfAndHalfBill("Kafe"), by: host.id)

        // Each bill reconciles alone: Bob floors, the host absorbs 1.
        for bill in room.bills {
            let single = try SettlementCalculator.settle(
                bill: bill, memberIDs: [host.id, bob.id], hostMemberID: host.id
            )
            #expect(single.settlement(for: bob.id)?.totalOwed == 2_500)
            #expect(single.settlement(for: host.id)?.totalOwed == 2_501)
            #expect(single.roundingRemainder == 1)
        }

        // The room is the sum of the already-rounded bills — nothing lost,
        // nothing invented, and NOT the 5.001 a room-level rounding of
        // Bob's exact total would produce.
        let settlement = try SettlementCalculator.settle(room: room)
        #expect(settlement.settlement(for: bob.id)?.totalOwed == 5_000)
        #expect(settlement.settlement(for: host.id)?.totalOwed == 5_002)
        #expect(settlement.roundingRemainder == 2)
        #expect(settlement.grandTotal == 10_002)
        let sum = settlement.memberSettlements.reduce(0) { $0 + $1.totalOwed }
        #expect(sum == settlement.grandTotal)
    }

    @Test("Single claimant owes the exact bill total; nothing to absorb")
    func singleClaimant() throws {
        // The sole claimant owes the whole bill — subtotal plus the printed tax.
        let bill = Bill(merchantName: "Warung", tax: 1_000,
                        items: [claimedItem(price: 10_001, by: bobID)])
        let settlement = try SettlementCalculator.settle(
            bill: bill, memberIDs: [hostID, bobID], hostMemberID: hostID
        )
        #expect(settlement.taxTotal == 1_000)
        #expect(settlement.settlement(for: bobID)?.totalOwed == 11_001)
        #expect(settlement.settlement(for: hostID)?.totalOwed == 0)
        #expect(settlement.roundingRemainder == 0)
    }

    @Test("Everyone on one item: floors for members, host absorbs the crumb")
    func everyoneOnOneItem() throws {
        let itemID = UUID()
        let item = BillItem(id: itemID, name: "Kentang", unitPrice: 10_000,
                            claimState: .claimed([
                                Claim(itemID: itemID, memberID: hostID, portion: Fraction(1, 3)),
                                Claim(itemID: itemID, memberID: bobID, portion: Fraction(1, 3)),
                                Claim(itemID: itemID, memberID: caraID, portion: Fraction(1, 3)),
                            ]))
        let bill = Bill(merchantName: "Warung", items: [item])
        let settlement = try SettlementCalculator.settle(
            bill: bill, memberIDs: [hostID, bobID, caraID], hostMemberID: hostID
        )
        // 10.000 / 3 = 3.333,3̅ — members pay the floor, host takes the rest.
        #expect(settlement.settlement(for: bobID)?.totalOwed == 3_333)
        #expect(settlement.settlement(for: caraID)?.totalOwed == 3_333)
        #expect(settlement.settlement(for: hostID)?.totalOwed == 3_334)
        #expect(settlement.roundingRemainder == 1)
        let sum = settlement.memberSettlements.reduce(0) { $0 + $1.totalOwed }
        #expect(sum == 10_000)
    }

    // MARK: - Property: totals always reconcile

    @Test("Randomized claims: member totals always sum to the exact bill total",
          arguments: UInt64(0)..<60)
    func totalsAlwaysReconcile(seed: UInt64) throws {
        var rng = SeededGenerator(seed: seed)
        let memberCount = Int.random(in: 2...6, using: &rng)
        let memberIDs = (0..<memberCount).map { _ in UUID() }
        let hostID = memberIDs.randomElement(using: &rng)!

        let itemCount = Int.random(in: 1...12, using: &rng)
        let items = (0..<itemCount).map { _ -> BillItem in
            let price = Int.random(in: 500...300_000, using: &rng)
            let itemID = UUID()
            let claims: [Claim]
            switch Int.random(in: 0..<10, using: &rng) {
            case 0..<6:
                // Single claimer.
                claims = [Claim(itemID: itemID, memberID: memberIDs.randomElement(using: &rng)!, portion: .one)]
            case 6..<9:
                // Equal split among a random subset.
                let claimers = memberIDs.shuffled(using: &rng)
                    .prefix(Int.random(in: 2...memberCount, using: &rng))
                claims = claimers.map {
                    Claim(itemID: itemID, memberID: $0, portion: Fraction(1, claimers.count))
                }
            default:
                // Uneven rational portions: k positive numerators summing to d.
                let claimers = Array(memberIDs.shuffled(using: &rng)
                    .prefix(Int.random(in: 2...memberCount, using: &rng)))
                let denominator = Int.random(in: claimers.count...(claimers.count + 6), using: &rng)
                var numerators = Array(repeating: 1, count: claimers.count)
                for _ in 0..<(denominator - claimers.count) {
                    numerators[Int.random(in: 0..<claimers.count, using: &rng)] += 1
                }
                claims = zip(claimers, numerators).map {
                    Claim(itemID: itemID, memberID: $0, portion: Fraction($1, denominator))
                }
            }
            return BillItem(id: itemID, name: "Item", unitPrice: price, claimState: .claimed(claims))
        }

        let subtotal = items.reduce(0) { $0 + $1.unitPrice }
        let bill = Bill(
            merchantName: "Random Warung",
            tax: Int.random(in: 0...(subtotal / 5 + 1), using: &rng),
            serviceCharge: Int.random(in: 0...(subtotal / 10 + 1), using: &rng),
            // Discount stays within the subtotal so the total never goes negative.
            discount: Int.random(in: 0...max(subtotal / 4, 1), using: &rng),
            items: items
        )

        let settlement = try SettlementCalculator.settle(
            bill: bill, memberIDs: memberIDs, hostMemberID: hostID
        )

        // Grand total is exactly subtotal + tax + service − discount.
        #expect(settlement.grandTotal
            == settlement.billSubtotal + settlement.taxTotal + settlement.serviceTotal - settlement.discountTotal)

        // Every column reconciles exactly.
        #expect(settlement.memberSettlements.reduce(0) { $0 + $1.subtotal } == settlement.billSubtotal)
        #expect(settlement.memberSettlements.reduce(0) { $0 + $1.taxShare } == settlement.taxTotal)
        #expect(settlement.memberSettlements.reduce(0) { $0 + $1.serviceShare } == settlement.serviceTotal)
        #expect(settlement.memberSettlements.reduce(0) { $0 + $1.discountShare } == settlement.discountTotal)
        #expect(settlement.memberSettlements.reduce(0) { $0 + $1.totalOwed } == settlement.grandTotal)

        // Per-member consistency and sanity.
        for member in settlement.memberSettlements {
            #expect(member.totalOwed
                == member.subtotal + member.taxShare + member.serviceShare - member.discountShare)
            #expect(member.subtotal >= 0)
            #expect(member.taxShare >= 0)
            #expect(member.serviceShare >= 0)
            // Non-host members get a non-negative credit; the host may take a
            // negative discount share to absorb their rounded-up credits.
            if member.memberID != hostID {
                #expect(member.discountShare >= 0)
            }
        }

        // No non-host member overpays their exact share (charges floored,
        // discount ceiled); the host absorbs every column's remainder.
        #expect(settlement.roundingRemainder >= 0)
        #expect(settlement.roundingRemainder < 4 * memberCount)
    }

    @Test("Discount is allocated proportionally and reconciles exactly")
    func discountProportional() throws {
        // Bob claims 3× Cara; the discount credit must split 3:1 too.
        let items = [
            claimedItem(price: 150_000, by: bobID),
            claimedItem(price: 50_000, by: caraID),
        ]
        let bill = Bill(merchantName: "Kafe", tax: 20_000, discount: 8_000, items: items)
        let settlement = try SettlementCalculator.settle(
            bill: bill, memberIDs: [hostID, bobID, caraID], hostMemberID: hostID
        )
        #expect(settlement.discountTotal == 8_000)
        #expect(settlement.grandTotal == 200_000 + 20_000 - 8_000)

        let bob = try #require(settlement.settlement(for: bobID))
        let cara = try #require(settlement.settlement(for: caraID))
        // 8.000 × 150/200 = 6.000 for Bob, 8.000 × 50/200 = 2.000 for Cara.
        #expect(bob.discountShare == 6_000)
        #expect(cara.discountShare == 2_000)
        #expect(bob.totalOwed == 150_000 + 15_000 - 6_000)
        #expect(cara.totalOwed == 50_000 + 5_000 - 2_000)

        let sum = settlement.memberSettlements.reduce(0) { $0 + $1.totalOwed }
        #expect(sum == settlement.grandTotal)
    }

    // MARK: - Helpers

    private func claimedItem(price: Int, by memberID: UUID) -> BillItem {
        let id = UUID()
        return BillItem(id: id, name: "Item", unitPrice: price,
                        claimState: .claimed([Claim(itemID: id, memberID: memberID, portion: .one)]))
    }
}
