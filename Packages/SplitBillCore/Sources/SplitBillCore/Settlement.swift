import Foundation

/// One member's share of a settled bill, in whole rupiah.
/// `totalOwed == subtotal + taxShare + serviceShare - discountShare` always holds.
public struct MemberSettlement: Sendable, Hashable {
    public let memberID: UUID
    public let subtotal: Int
    public let taxShare: Int
    public let serviceShare: Int
    /// The member's proportional slice of the bill discount (a credit).
    public let discountShare: Int
    public let totalOwed: Int

    public init(
        memberID: UUID,
        subtotal: Int,
        taxShare: Int,
        serviceShare: Int,
        discountShare: Int = 0,
        totalOwed: Int
    ) {
        self.memberID = memberID
        self.subtotal = subtotal
        self.taxShare = taxShare
        self.serviceShare = serviceShare
        self.discountShare = discountShare
        self.totalOwed = totalOwed
    }
}

/// The full settlement of a bill (or a whole room): per-member breakdowns
/// that reconcile exactly with the bill totals.
public struct Settlement: Sendable, Hashable {
    public let hostMemberID: UUID
    /// One entry per member, in the order the member IDs were supplied.
    public let memberSettlements: [MemberSettlement]
    public let billSubtotal: Int
    public let taxTotal: Int
    public let serviceTotal: Int
    public let discountTotal: Int
    /// `billSubtotal + taxTotal + serviceTotal - discountTotal`; member totals
    /// sum to this exactly.
    public let grandTotal: Int
    /// Whole rupiah the host absorbed on top of their own floored exact share
    /// so that everything reconciles. Always `>= 0`.
    public let roundingRemainder: Int

    public init(
        hostMemberID: UUID,
        memberSettlements: [MemberSettlement],
        billSubtotal: Int,
        taxTotal: Int,
        serviceTotal: Int,
        discountTotal: Int = 0,
        grandTotal: Int,
        roundingRemainder: Int
    ) {
        self.hostMemberID = hostMemberID
        self.memberSettlements = memberSettlements
        self.billSubtotal = billSubtotal
        self.taxTotal = taxTotal
        self.serviceTotal = serviceTotal
        self.discountTotal = discountTotal
        self.grandTotal = grandTotal
        self.roundingRemainder = roundingRemainder
    }

    public func settlement(for memberID: UUID) -> MemberSettlement? {
        memberSettlements.first { $0.memberID == memberID }
    }
}

/// Pure settlement math. No state — feed it a bill, get exact rupiah back.
///
/// Rules (see CLAUDE.md):
/// - Per-member subtotals come from claims, portion-aware, kept as exact fractions.
/// - Tax (PB1), service charge, and discount are the bill's stored whole-rupiah
///   amounts, each allocated **proportionally to each member's subtotal** —
///   never per head.
/// - Charge columns are rounded *down* for non-host members and the discount
///   (a credit) is rounded *up*, so no member ever overpays their exact share;
///   the host absorbs every column's remainder, so member totals sum to the
///   exact bill total.
public enum SettlementCalculator {
    /// Settles a single bill among `memberIDs` (which must include the host).
    /// Throws if any item is unclaimed or any claim is malformed.
    public static func settle(
        bill: Bill,
        memberIDs: [UUID],
        hostMemberID: UUID
    ) throws -> Settlement {
        guard memberIDs.contains(hostMemberID) else {
            throw SettlementError.hostNotIncluded
        }
        let knownMembers = Set(memberIDs)

        // Exact per-member subtotals from claims.
        var exactSubtotal: [UUID: Fraction] = [:]
        for id in memberIDs {
            exactSubtotal[id] = .zero
        }
        var unclaimed: [UUID] = []
        for item in bill.items {
            switch item.claimState {
            case .unclaimed:
                unclaimed.append(item.id)
            case .forceAssigned(let memberID):
                guard knownMembers.contains(memberID) else {
                    throw SettlementError.unknownClaimer(itemID: item.id, memberID: memberID)
                }
                exactSubtotal[memberID]! += Fraction(item.unitPrice)
            case .claimed(let claims):
                let portionSum = claims.reduce(Fraction.zero) { $0 + $1.portion }
                guard !claims.isEmpty,
                      portionSum == .one,
                      claims.allSatisfy({ $0.portion > .zero }) else {
                    throw SettlementError.invalidPortions(itemID: item.id)
                }
                for claim in claims {
                    guard knownMembers.contains(claim.memberID) else {
                        throw SettlementError.unknownClaimer(itemID: item.id, memberID: claim.memberID)
                    }
                    exactSubtotal[claim.memberID]! += claim.portion * item.unitPrice
                }
            }
        }
        guard unclaimed.isEmpty else {
            throw SettlementError.unclaimedItems(unclaimed)
        }

        // Bill-level totals, rounded to whole rupiah like the printed receipt.
        // Service charge always applies to the subtotal; the tax basis decides
        // whether PB1 applies to the subtotal alone or to subtotal + service.
        let billSubtotal = bill.subtotal
        let serviceTotal = bill.serviceChargeTotal
        let taxTotal = bill.taxTotal
        let discountTotal = bill.discountTotal
        let grandTotal = billSubtotal + taxTotal + serviceTotal - discountTotal

        // Proportional shares: member share of a column = column * subtotal_m / S.
        func exactShare(of columnTotal: Int, for memberID: UUID) -> Fraction {
            guard billSubtotal > 0 else { return .zero }
            return Fraction(columnTotal) * exactSubtotal[memberID]! / Fraction(billSubtotal)
        }

        // Non-host members pay the floor of each charge column and take the
        // ceil of the discount (a credit), so they never overpay their exact
        // share. The host takes every column's remainder, reconciling exactly.
        var settlements: [MemberSettlement] = []
        var allocatedSubtotal = 0
        var allocatedTax = 0
        var allocatedService = 0
        var allocatedDiscount = 0
        for memberID in memberIDs where memberID != hostMemberID {
            let subtotal = exactSubtotal[memberID]!.flooredValue
            let taxShare = exactShare(of: taxTotal, for: memberID).flooredValue
            let serviceShare = exactShare(of: serviceTotal, for: memberID).flooredValue
            let discountShare = exactShare(of: discountTotal, for: memberID).ceiledValue
            allocatedSubtotal += subtotal
            allocatedTax += taxShare
            allocatedService += serviceShare
            allocatedDiscount += discountShare
            settlements.append(MemberSettlement(
                memberID: memberID,
                subtotal: subtotal,
                taxShare: taxShare,
                serviceShare: serviceShare,
                discountShare: discountShare,
                totalOwed: subtotal + taxShare + serviceShare - discountShare
            ))
        }

        let hostSubtotal = billSubtotal - allocatedSubtotal
        let hostTax = taxTotal - allocatedTax
        let hostService = serviceTotal - allocatedService
        let hostDiscount = discountTotal - allocatedDiscount
        let hostTotal = hostSubtotal + hostTax + hostService - hostDiscount
        let hostFlooredExact = exactSubtotal[hostMemberID]!.flooredValue
            + exactShare(of: taxTotal, for: hostMemberID).flooredValue
            + exactShare(of: serviceTotal, for: hostMemberID).flooredValue
            - exactShare(of: discountTotal, for: hostMemberID).ceiledValue
        let hostSettlement = MemberSettlement(
            memberID: hostMemberID,
            subtotal: hostSubtotal,
            taxShare: hostTax,
            serviceShare: hostService,
            discountShare: hostDiscount,
            totalOwed: hostTotal
        )
        let hostIndex = memberIDs.firstIndex(of: hostMemberID)!
        settlements.insert(hostSettlement, at: hostIndex)

        return Settlement(
            hostMemberID: hostMemberID,
            memberSettlements: settlements,
            billSubtotal: billSubtotal,
            taxTotal: taxTotal,
            serviceTotal: serviceTotal,
            discountTotal: discountTotal,
            grandTotal: grandTotal,
            roundingRemainder: hostTotal - hostFlooredExact
        )
    }

    /// Settles every bill in a room and aggregates per member. Rounding is
    /// done per bill (each receipt reconciles on its own, like the paper it
    /// came from), then whole-rupiah amounts are summed.
    public static func settle(room: Room) throws -> Settlement {
        let memberIDs = room.members.map(\.id)
        var subtotalByMember: [UUID: Int] = [:]
        var taxByMember: [UUID: Int] = [:]
        var serviceByMember: [UUID: Int] = [:]
        var discountByMember: [UUID: Int] = [:]
        var billSubtotal = 0
        var taxTotal = 0
        var serviceTotal = 0
        var discountTotal = 0
        var roundingRemainder = 0

        for bill in room.bills {
            let settled = try settle(bill: bill, memberIDs: memberIDs, hostMemberID: room.hostMemberID)
            billSubtotal += settled.billSubtotal
            taxTotal += settled.taxTotal
            serviceTotal += settled.serviceTotal
            discountTotal += settled.discountTotal
            roundingRemainder += settled.roundingRemainder
            for member in settled.memberSettlements {
                subtotalByMember[member.memberID, default: 0] += member.subtotal
                taxByMember[member.memberID, default: 0] += member.taxShare
                serviceByMember[member.memberID, default: 0] += member.serviceShare
                discountByMember[member.memberID, default: 0] += member.discountShare
            }
        }

        let settlements = memberIDs.map { id in
            let subtotal = subtotalByMember[id, default: 0]
            let tax = taxByMember[id, default: 0]
            let service = serviceByMember[id, default: 0]
            let discount = discountByMember[id, default: 0]
            return MemberSettlement(
                memberID: id,
                subtotal: subtotal,
                taxShare: tax,
                serviceShare: service,
                discountShare: discount,
                totalOwed: subtotal + tax + service - discount
            )
        }

        return Settlement(
            hostMemberID: room.hostMemberID,
            memberSettlements: settlements,
            billSubtotal: billSubtotal,
            taxTotal: taxTotal,
            serviceTotal: serviceTotal,
            discountTotal: discountTotal,
            grandTotal: billSubtotal + taxTotal + serviceTotal - discountTotal,
            roundingRemainder: roundingRemainder
        )
    }
}
