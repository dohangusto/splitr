import Foundation

/// One member's stake in one bill item. Portions are exact fractions;
/// the portions on a claimed item always sum to exactly 1.
public struct Claim: Sendable, Hashable, Codable {
    public let itemID: UUID
    public let memberID: UUID
    public let portion: Fraction

    public init(itemID: UUID, memberID: UUID, portion: Fraction) {
        self.itemID = itemID
        self.memberID = memberID
        self.portion = portion
    }
}

/// Claim state of a single claimable unit.
public enum ClaimState: Sendable, Hashable, Codable {
    case unclaimed
    /// Claimed by one or more members; portions sum to exactly 1.
    case claimed([Claim])
    /// Assigned by the host, overriding any prior claim.
    case forceAssigned(UUID)

    /// IDs of the members currently holding this item, if any.
    public var claimerIDs: [UUID] {
        switch self {
        case .unclaimed:
            return []
        case .claimed(let claims):
            return claims.map(\.memberID)
        case .forceAssigned(let memberID):
            return [memberID]
        }
    }
}
