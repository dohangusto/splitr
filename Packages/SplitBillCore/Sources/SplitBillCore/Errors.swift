import Foundation

/// Errors from room membership, state transitions, and payment tracking.
public enum RoomError: Error, Equatable, Sendable {
    /// The acting member is not the host; only the host may perform this action.
    case notHost(UUID)
    case invalidTransition(from: RoomState, to: RoomState)
    /// The room is closed; closed is terminal and read-only.
    case roomIsClosed
    case joiningNotAllowed(RoomState)
    case memberAlreadyJoined(UUID)
    case memberNotFound(UUID)
    case cannotKickHost
    case billAlreadyAdded(UUID)
    case billEditingNotAllowed(RoomState)
    case paymentUpdateNotAllowed(RoomState)
    /// The host fronted the bill; they have no payment of their own to track.
    case hostHasNoPayment
}

/// Errors from claiming items.
public enum ClaimError: Error, Equatable, Sendable {
    case claimingNotAllowed(RoomState)
    case billNotFound(UUID)
    case itemNotFound(UUID)
    case memberNotFound(UUID)
    /// The item is already held; `claimers` identifies who — this is what the
    /// sync layer surfaces as "already claimed by X" on a lost claim race.
    case alreadyClaimed(itemID: UUID, claimers: [UUID])
    case noClaimers
    case duplicateClaimers
    case nonPositivePortion
    case portionsMustSumToOne(actual: Fraction)
    case notAClaimer(itemID: UUID, memberID: UUID)
    /// The member already holds a share of this item and cannot join it again.
    case alreadyAClaimer(itemID: UUID, memberID: UUID)
}

/// Errors from settlement computation.
public enum SettlementError: Error, Equatable, Sendable {
    /// Settlement requires every item claimed or force-assigned.
    case unclaimedItems([UUID])
    /// An item's claim portions are empty, non-positive, or do not sum to 1.
    case invalidPortions(itemID: UUID)
    /// A claim references a member not in the provided member list.
    case unknownClaimer(itemID: UUID, memberID: UUID)
    /// The host must be among the members being settled.
    case hostNotIncluded
}
