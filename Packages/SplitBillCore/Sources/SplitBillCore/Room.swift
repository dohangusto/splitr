import Foundation

/// A shared bill-splitting session. The room is the aggregate root: all
/// mutations (state transitions, membership, claims, payments) go through
/// its throwing methods so invariants hold everywhere.
///
/// Only the host advances the state machine; members act *within* states.
public struct Room: Identifiable, Sendable, Hashable, Codable {
    public let id: UUID
    public var name: String
    public private(set) var state: RoomState
    public let hostMemberID: UUID
    public let createdAt: Date
    public private(set) var members: [Member]
    public private(set) var bills: [Bill]

    /// Rehydrates a room from persisted state (CloudKit records, caches).
    /// For persistence layers only: trusts the stored state and does not
    /// re-validate invariants — never build new rooms with this.
    public init(
        rehydrating id: UUID,
        name: String,
        state: RoomState,
        hostMemberID: UUID,
        createdAt: Date,
        members: [Member],
        bills: [Bill]
    ) {
        self.id = id
        self.name = name
        self.state = state
        self.hostMemberID = hostMemberID
        self.createdAt = createdAt
        self.members = members
        self.bills = bills
    }

    /// Creates a room in `.open` with the host as its first member.
    public init(id: UUID = UUID(), name: String, host: Member, createdAt: Date = Date()) {
        var host = host
        host.isHost = true
        self.id = id
        self.name = name
        self.state = .open
        self.hostMemberID = host.id
        self.createdAt = createdAt
        self.members = [host]
        self.bills = []
    }

    // MARK: - Queries

    public func member(withID id: UUID) -> Member? {
        members.first { $0.id == id }
    }

    public func bill(withID id: UUID) -> Bill? {
        bills.first { $0.id == id }
    }

    /// Every claim a member currently holds, across all bills.
    /// Force-assigned items count as a whole-item (portion 1) claim.
    public func claims(for memberID: UUID) -> [Claim] {
        bills.flatMap { bill in
            bill.items.flatMap { item -> [Claim] in
                switch item.claimState {
                case .unclaimed:
                    return []
                case .claimed(let claims):
                    return claims.filter { $0.memberID == memberID }
                case .forceAssigned(let assignee):
                    return assignee == memberID
                        ? [Claim(itemID: item.id, memberID: memberID, portion: .one)]
                        : []
                }
            }
        }
    }

    /// Whole-rupiah value of everything the member has claimed so far,
    /// portion-aware, floored — the "your items so far" running total shown
    /// during claiming (before tax and service are allocated).
    public func claimedSubtotal(for memberID: UUID) -> Int {
        claims(for: memberID)
            .reduce(Fraction.zero) { total, claim in
                let price = bills
                    .lazy
                    .compactMap { $0.item(withID: claim.itemID) }
                    .first?.unitPrice ?? 0
                return total + claim.portion * price
            }
            .flooredValue
    }

    // MARK: - State machine (host-only)

    /// Advances `open → claiming → settling → closed`. Throws from `.closed`.
    public mutating func advance(by actorID: UUID) throws {
        try requireHost(actorID)
        switch state {
        case .open:
            state = .claiming
        case .claiming:
            state = .settling
        case .settling:
            state = .closed
        case .closed:
            throw RoomError.roomIsClosed
        }
    }

    /// The single allowed rollback: `settling → claiming`.
    public mutating func rollbackToClaiming(by actorID: UUID) throws {
        try requireHost(actorID)
        guard state == .settling else {
            throw RoomError.invalidTransition(from: state, to: .claiming)
        }
        state = .claiming
    }

    // MARK: - Membership

    /// Members may join during `.open` and `.claiming` only (late joiners
    /// are allowed while claiming). The joiner is never the host.
    public mutating func join(_ member: Member) throws {
        guard state == .open || state == .claiming else {
            throw RoomError.joiningNotAllowed(state)
        }
        guard self.member(withID: member.id) == nil else {
            throw RoomError.memberAlreadyJoined(member.id)
        }
        var member = member
        member.isHost = false
        member.paymentStatus = .none
        members.append(member)
    }

    /// Removes a member (host-only) and returns every item they were part of
    /// — sole claims, shared claims, and force-assignments — to `.unclaimed`.
    public mutating func kick(memberID: UUID, by actorID: UUID) throws {
        try requireHost(actorID)
        guard state != .closed else { throw RoomError.roomIsClosed }
        guard memberID != hostMemberID else { throw RoomError.cannotKickHost }
        guard let index = members.firstIndex(where: { $0.id == memberID }) else {
            throw RoomError.memberNotFound(memberID)
        }
        members.remove(at: index)
        for billIndex in bills.indices {
            for itemIndex in bills[billIndex].items.indices {
                if bills[billIndex].items[itemIndex].claimState.claimerIDs.contains(memberID) {
                    bills[billIndex].items[itemIndex].claimState = .unclaimed
                }
            }
        }
    }

    // MARK: - Bills (host-only)

    public mutating func addBill(_ bill: Bill, by actorID: UUID) throws {
        try requireHost(actorID)
        guard state == .open || state == .claiming else {
            throw RoomError.billEditingNotAllowed(state)
        }
        guard self.bill(withID: bill.id) == nil else {
            throw RoomError.billAlreadyAdded(bill.id)
        }
        bills.append(bill)
    }

    /// Replaces an existing bill wholesale (OCR corrections, wrong prices).
    /// Allowed while `.open` or `.claiming` — a wrong price is often only
    /// spotted once people start claiming. The caller is responsible for
    /// carrying existing claims into the replacement items; this method
    /// replaces wholesale and will not resurrect them.
    public mutating func updateBill(_ bill: Bill, by actorID: UUID) throws {
        try requireHost(actorID)
        guard state == .open || state == .claiming else {
            throw RoomError.billEditingNotAllowed(state)
        }
        guard let index = bills.firstIndex(where: { $0.id == bill.id }) else {
            throw RoomError.billNotFound(bill.id)
        }
        bills[index] = bill
    }

    /// Removes a bill entirely (e.g. scanned the wrong receipt).
    /// `.open` only — never out from under claimers.
    public mutating func removeBill(withID billID: UUID, by actorID: UUID) throws {
        try requireHost(actorID)
        guard state == .open else {
            throw RoomError.billEditingNotAllowed(state)
        }
        guard bills.contains(where: { $0.id == billID }) else {
            throw RoomError.billNotFound(billID)
        }
        bills.removeAll { $0.id == billID }
    }

    // MARK: - Claiming (members, during .claiming)

    /// Claims a whole item for one member.
    public mutating func claim(itemID: UUID, in billID: UUID, as memberID: UUID) throws {
        try claim(itemID: itemID, in: billID, portions: [(memberID, .one)])
    }

    /// Claims an item shared equally among several members (1/n each).
    public mutating func claimShared(itemID: UUID, in billID: UUID, among memberIDs: [UUID]) throws {
        try claim(
            itemID: itemID,
            in: billID,
            portions: memberIDs.map { ($0, Fraction(1, max(memberIDs.count, 1))) }
        )
    }

    /// Claims an item with explicit portions. Portions must be positive and
    /// sum to exactly 1. Claiming an item that is already claimed or
    /// force-assigned throws `ClaimError.alreadyClaimed` naming the holders.
    public mutating func claim(
        itemID: UUID,
        in billID: UUID,
        portions: [(memberID: UUID, portion: Fraction)]
    ) throws {
        guard state == .claiming else { throw ClaimError.claimingNotAllowed(state) }
        guard !portions.isEmpty else { throw ClaimError.noClaimers }
        guard Set(portions.map(\.memberID)).count == portions.count else {
            throw ClaimError.duplicateClaimers
        }
        for (memberID, portion) in portions {
            guard member(withID: memberID) != nil else {
                throw ClaimError.memberNotFound(memberID)
            }
            guard portion > .zero else { throw ClaimError.nonPositivePortion }
        }
        let total = portions.reduce(Fraction.zero) { $0 + $1.portion }
        guard total == .one else {
            throw ClaimError.portionsMustSumToOne(actual: total)
        }
        try mutateItem(itemID: itemID, in: billID) { item in
            guard case .unclaimed = item.claimState else {
                throw ClaimError.alreadyClaimed(
                    itemID: itemID,
                    claimers: item.claimState.claimerIDs
                )
            }
            item.claimState = .claimed(portions.map {
                Claim(itemID: itemID, memberID: $0.memberID, portion: $0.portion)
            })
        }
    }

    /// Joins an existing claim: the item is re-split equally among the current
    /// claimers plus the joiner (custom portions are reset to the equal split).
    /// Joining an unclaimed item claims it whole; force-assigned items are
    /// host-owned and conflict.
    public mutating func joinClaim(itemID: UUID, in billID: UUID, as memberID: UUID) throws {
        guard state == .claiming else { throw ClaimError.claimingNotAllowed(state) }
        guard member(withID: memberID) != nil else {
            throw ClaimError.memberNotFound(memberID)
        }
        try mutateItem(itemID: itemID, in: billID) { item in
            switch item.claimState {
            case .unclaimed:
                item.claimState = .claimed([Claim(itemID: itemID, memberID: memberID, portion: .one)])
            case .claimed(let claims):
                guard !claims.contains(where: { $0.memberID == memberID }) else {
                    throw ClaimError.alreadyAClaimer(itemID: itemID, memberID: memberID)
                }
                let claimers = claims.map(\.memberID) + [memberID]
                item.claimState = .claimed(claimers.map {
                    Claim(itemID: itemID, memberID: $0, portion: Fraction(1, claimers.count))
                })
            case .forceAssigned(let assignee):
                throw ClaimError.alreadyClaimed(itemID: itemID, claimers: [assignee])
            }
        }
    }

    /// A claimer gives an item back. Shared claims return the whole item to
    /// `.unclaimed` (remaining portions would no longer sum to 1).
    /// Force-assignments can only be undone by the host via `forceAssign`.
    public mutating func releaseClaim(itemID: UUID, in billID: UUID, as memberID: UUID) throws {
        guard state == .claiming else { throw ClaimError.claimingNotAllowed(state) }
        try mutateItem(itemID: itemID, in: billID) { item in
            guard case .claimed(let claims) = item.claimState,
                  claims.contains(where: { $0.memberID == memberID }) else {
                throw ClaimError.notAClaimer(itemID: itemID, memberID: memberID)
            }
            item.claimState = .unclaimed
        }
    }

    /// Host assigns an item to a member, overriding any existing claim state.
    public mutating func forceAssign(
        itemID: UUID,
        in billID: UUID,
        to memberID: UUID,
        by actorID: UUID
    ) throws {
        try requireHost(actorID)
        guard state == .claiming else { throw ClaimError.claimingNotAllowed(state) }
        guard member(withID: memberID) != nil else {
            throw ClaimError.memberNotFound(memberID)
        }
        try mutateItem(itemID: itemID, in: billID) { item in
            item.claimState = .forceAssigned(memberID)
        }
    }

    // MARK: - Payment tracking (during .settling)

    /// A member marks that they have transferred money to the host.
    public mutating func markPaid(as memberID: UUID) throws {
        guard state == .settling else { throw RoomError.paymentUpdateNotAllowed(state) }
        guard memberID != hostMemberID else { throw RoomError.hostHasNoPayment }
        guard let index = members.firstIndex(where: { $0.id == memberID }) else {
            throw RoomError.memberNotFound(memberID)
        }
        members[index].paymentStatus = .memberMarkedPaid
    }

    /// Host confirms money was received (allowed even if the member has not
    /// tapped "I've paid" — e.g. cash handed over directly).
    public mutating func confirmPayment(of memberID: UUID, by actorID: UUID) throws {
        try requireHost(actorID)
        guard state == .settling else { throw RoomError.paymentUpdateNotAllowed(state) }
        guard memberID != hostMemberID else { throw RoomError.hostHasNoPayment }
        guard let index = members.firstIndex(where: { $0.id == memberID }) else {
            throw RoomError.memberNotFound(memberID)
        }
        members[index].paymentStatus = .hostConfirmed
    }

    // MARK: - Private

    private func requireHost(_ actorID: UUID) throws {
        guard actorID == hostMemberID else { throw RoomError.notHost(actorID) }
    }

    private mutating func mutateItem(
        itemID: UUID,
        in billID: UUID,
        _ body: (inout BillItem) throws -> Void
    ) throws {
        guard let billIndex = bills.firstIndex(where: { $0.id == billID }) else {
            throw ClaimError.billNotFound(billID)
        }
        guard let itemIndex = bills[billIndex].items.firstIndex(where: { $0.id == itemID }) else {
            throw ClaimError.itemNotFound(itemID)
        }
        try body(&bills[billIndex].items[itemIndex])
    }
}
