import Foundation
import SplitBillCore

/// Shared claim-state reading for every surface that renders items —
/// host oversight (ClaimingView) and the member surface (MemberClaim) read
/// the same substrate; only the controls differ.
extension BillItem {
    /// Everyone currently on this item (claimers, or the force-assignee).
    var participantIDs: [UUID] {
        switch claimState {
        case .unclaimed: return []
        case .claimed(let claims): return claims.map(\.memberID)
        case .forceAssigned(let memberID): return [memberID]
        }
    }

    func involves(_ memberID: UUID) -> Bool {
        participantIDs.contains(memberID)
    }

    /// True when exactly one *voluntary* claimer holds the whole item.
    /// Force-assigned items are the host's call, not an exclusive claim.
    var isExclusivelyClaimed: Bool {
        if case .claimed(let claims) = claimState { return claims.count == 1 }
        return false
    }

    var isSharedClaim: Bool {
        if case .claimed(let claims) = claimState { return claims.count > 1 }
        return false
    }

    var isForceAssigned: Bool {
        if case .forceAssigned = claimState { return true }
        return false
    }

    /// Display names of everyone on the item, in claim order.
    func participantNames(in room: Room) -> [String] {
        participantIDs.map { room.member(withID: $0)?.displayName ?? "someone" }
    }
}
