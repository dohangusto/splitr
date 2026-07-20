import Foundation

/// One member's share of a settled bill, in whole rupiah.
/// `totalOwed == subtotal + taxShare + serviceShare` always holds.
public struct MemberSettlement: Sendable, Hashable {
    public let memberID: UUID
    public let subtotal: Int
    public let taxShare: Int
    public let serviceShare: Int
    public let totalOwed: Int

    public init(memberID: UUID, subtotal: Int, taxShare: Int, serviceShare: Int, totalOwed: Int) {
        self.memberID = memberID
        self.subtotal = subtotal
        self.taxShare = taxShare
        self.serviceShare = serviceShare
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
    /// `billSubtotal + taxTotal + serviceTotal`; member totals sum to this exactly.
    public let grandTotal: Int
    /// Whole rupiah the host absorbed on top of their own floored exact share
    /// so that everything reconciles. Always `>= 0`.
    public let roundingRemainder: Int

    public func settlement(for memberID: UUID) -> MemberSettlement? {
        memberSettlements.first { $0.memberID == memberID }
    }
}

/// Pure settlement math. No state — feed it a bill, get exact rupiah back.
///
/// Rules (see CLAUDE.md):
/// - Per-member subtotals come from claims, portion-aware, kept as exact fractions.
/// - Service charge is computed on the bill subtotal; tax (PB1) is computed on
///   the bill's `taxBasis` (subtotal, or subtotal + service). Both are
///   allocated **proportionally to each member's subtotal** — never per head.
/// - Every non-host amount is rounded *down* to whole rupiah; the host absorbs
///   whatever remains, so the sum of member totals equals the exact bill total
///   and no member ever overpays their exact share.
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
        let grandTotal = billSubtotal + taxTotal + serviceTotal

        // Proportional shares: member share of tax = taxTotal * subtotal_m / S.
        func exactShare(of columnTotal: Int, for memberID: UUID) -> Fraction {
            guard billSubtotal > 0 else { return .zero }
            return Fraction(columnTotal) * exactSubtotal[memberID]! / Fraction(billSubtotal)
        }

        // Non-host members pay the floor of their exact amounts; the host
        // takes each column's remainder so every column reconciles exactly.
        var settlements: [MemberSettlement] = []
        var allocatedSubtotal = 0
        var allocatedTax = 0
        var allocatedService = 0
        for memberID in memberIDs where memberID != hostMemberID {
            let subtotal = exactSubtotal[memberID]!.flooredValue
            let taxShare = exactShare(of: taxTotal, for: memberID).flooredValue
            let serviceShare = exactShare(of: serviceTotal, for: memberID).flooredValue
            allocatedSubtotal += subtotal
            allocatedTax += taxShare
            allocatedService += serviceShare
            settlements.append(MemberSettlement(
                memberID: memberID,
                subtotal: subtotal,
                taxShare: taxShare,
                serviceShare: serviceShare,
                totalOwed: subtotal + taxShare + serviceShare
            ))
        }

        let hostSubtotal = billSubtotal - allocatedSubtotal
        let hostTax = taxTotal - allocatedTax
        let hostService = serviceTotal - allocatedService
        let hostTotal = hostSubtotal + hostTax + hostService
        let hostFlooredExact = exactSubtotal[hostMemberID]!.flooredValue
            + exactShare(of: taxTotal, for: hostMemberID).flooredValue
            + exactShare(of: serviceTotal, for: hostMemberID).flooredValue
        let hostSettlement = MemberSettlement(
            memberID: hostMemberID,
            subtotal: hostSubtotal,
            taxShare: hostTax,
            serviceShare: hostService,
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
        var billSubtotal = 0
        var taxTotal = 0
        var serviceTotal = 0
        var roundingRemainder = 0

        for bill in room.bills {
            let settled = try settle(bill: bill, memberIDs: memberIDs, hostMemberID: room.hostMemberID)
            billSubtotal += settled.billSubtotal
            taxTotal += settled.taxTotal
            serviceTotal += settled.serviceTotal
            roundingRemainder += settled.roundingRemainder
            for member in settled.memberSettlements {
                subtotalByMember[member.memberID, default: 0] += member.subtotal
                taxByMember[member.memberID, default: 0] += member.taxShare
                serviceByMember[member.memberID, default: 0] += member.serviceShare
            }
        }

        let settlements = memberIDs.map { id in
            let subtotal = subtotalByMember[id, default: 0]
            let tax = taxByMember[id, default: 0]
            let service = serviceByMember[id, default: 0]
            return MemberSettlement(
                memberID: id,
                subtotal: subtotal,
                taxShare: tax,
                serviceShare: service,
                totalOwed: subtotal + tax + service
            )
        }

        return Settlement(
            hostMemberID: room.hostMemberID,
            memberSettlements: settlements,
            billSubtotal: billSubtotal,
            taxTotal: taxTotal,
            serviceTotal: serviceTotal,
            grandTotal: billSubtotal + taxTotal + serviceTotal,
            roundingRemainder: roundingRemainder
        )
    }
}
