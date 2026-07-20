import Foundation
import SplitBillCore

/// User-facing copy for store alerts, shared by every RoomStoring
/// implementation (mock and CloudKit).
enum StoreCopy {
    /// Maps Core's typed errors to user-facing alert copy.
    static func message(for error: Error, in room: Room) -> String {
        func name(_ id: UUID) -> String {
            room.member(withID: id)?.displayName ?? "someone"
        }
        switch error {
        case ClaimError.alreadyClaimed(_, let claimers):
            let names = claimers.map(name).joined(separator: ", ")
            return "Already claimed by \(names)."
        case ClaimError.alreadyAClaimer:
            return "You already have a share of this item."
        case ClaimError.notAClaimer:
            return "You haven't claimed this item."
        case ClaimError.claimingNotAllowed(let state):
            return "Items can't be changed while the room is \(state.rawValue)."
        case ClaimError.memberNotFound, RoomError.memberNotFound:
            return "That member is no longer in this room."
        case ClaimError.billNotFound, ClaimError.itemNotFound:
            return "That item is no longer on the bill."
        case ClaimError.portionsMustSumToOne, ClaimError.nonPositivePortion,
             ClaimError.noClaimers, ClaimError.duplicateClaimers:
            return "Those portions don't add up to a whole item."
        case RoomError.notHost:
            return "Only the host can do that."
        case RoomError.roomIsClosed:
            return "This room is closed and read-only."
        case RoomError.invalidTransition:
            return "The room can't move to that stage right now."
        case RoomError.joiningNotAllowed:
            return "New members can only join before settling starts."
        case RoomError.memberAlreadyJoined:
            return "That member is already in the room."
        case RoomError.cannotKickHost:
            return "The host can't be removed."
        case RoomError.billAlreadyAdded:
            return "That bill was already added."
        case RoomError.billNotFound:
            return "That bill is no longer in this room."
        case RoomError.billEditingNotAllowed:
            return "Bills can only be edited before claiming starts."
        case RoomError.paymentUpdateNotAllowed:
            return "Payments can only be updated while settling."
        case RoomError.hostHasNoPayment:
            return "The host paid the bill — there's nothing for them to pay back."
        default:
            return "Something went wrong. Please try again."
        }
    }
}
