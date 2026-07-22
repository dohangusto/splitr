import Foundation
import SplitBillCore

/// Core ⇄ JSON mapping — the one place that knows how domain types become
/// wire bytes and back. Mirrors `SplitBillSync`'s `RecordMapper` (Core ⇄
/// CKRecord); here the boundary is HTTP instead of CloudKit.
///
/// Member identity crosses the boundary as `UUID.uuidString`. On the way back
/// in, an invalid string is a decode failure, not a silent drop — a claim
/// state that can't be reconstructed exactly must fail loudly.
public enum RelayMapping {

    // MARK: - Errors

    public enum MappingError: Error, Equatable {
        /// A `participantId` on the wire was not a valid member UUID string.
        case invalidParticipantID(String)
        /// An `ItemDTO.id` was not a valid UUID string.
        case invalidItemID(String)
        /// `claimed` arrived with mismatched participant/portion array lengths.
        case portionCountMismatch(participants: Int, portions: Int)
    }

    // MARK: - Claim state

    public static func claimStateDTO(from state: ClaimState) -> ClaimStateDTO {
        switch state {
        case .unclaimed:
            return .unclaimed
        case .claimed(let claims):
            return .claimed(
                participantIds: claims.map { $0.memberID.uuidString },
                portions: claims.map(\.portion)
            )
        case .forceAssigned(let memberID):
            return .forceAssigned(participantId: memberID.uuidString)
        }
    }

    /// Rebuilds Core's `ClaimState`. `itemID` is needed because each `Claim`
    /// carries its item id; the DTO omits it (it's implied by the enclosing
    /// item) so we thread it back in here.
    public static func claimState(from dto: ClaimStateDTO, itemID: UUID) throws -> ClaimState {
        switch dto {
        case .unclaimed:
            return .unclaimed
        case .claimed(let participantIds, let portions):
            guard participantIds.count == portions.count else {
                throw MappingError.portionCountMismatch(
                    participants: participantIds.count, portions: portions.count
                )
            }
            let claims = try zip(participantIds, portions).map { id, portion -> Claim in
                guard let memberID = UUID(uuidString: id) else {
                    throw MappingError.invalidParticipantID(id)
                }
                return Claim(itemID: itemID, memberID: memberID, portion: portion)
            }
            return .claimed(claims)
        case .forceAssigned(let participantId):
            guard let memberID = UUID(uuidString: participantId) else {
                throw MappingError.invalidParticipantID(participantId)
            }
            return .forceAssigned(memberID)
        }
    }

    // MARK: - Items

    public static func itemDTO(from item: BillItem) -> ItemDTO {
        ItemDTO(
            id: item.id.uuidString,
            name: item.name,
            unitPrice: item.unitPrice,
            claimState: claimStateDTO(from: item.claimState)
        )
    }

    public static func billItem(from dto: ItemDTO) throws -> BillItem {
        guard let id = UUID(uuidString: dto.id) else {
            throw MappingError.invalidItemID(dto.id)
        }
        return BillItem(
            id: id,
            name: dto.name,
            unitPrice: dto.unitPrice,
            claimState: try claimState(from: dto.claimState, itemID: id)
        )
    }

    // MARK: - Participants

    /// One-way: Core `Member` → wire. The reverse doesn't exist by design —
    /// the relay never reconstructs a `Member` (host mints identity on drain),
    /// and `isHost` / `paymentStatus` are intentionally not on the wire.
    public static func participantDTO(from member: Member) -> ParticipantDTO {
        ParticipantDTO(
            participantId: member.id.uuidString,
            displayName: member.displayName,
            avatarEmoji: member.avatarEmoji
        )
    }

    // MARK: - Snapshot

    /// Builds a session snapshot from one bill plus the room's roster/state.
    /// A session is scoped to a single bill (the snapshot carries one set of
    /// rates and one item list) — the settlement inputs the clip needs.
    public static func snapshotDTO(
        sessionId: String,
        bill: Bill,
        participants: [Member],
        roomState: RoomState
    ) -> SnapshotDTO {
        SnapshotDTO(
            sessionId: sessionId,
            merchantName: bill.merchantName,
            tax: bill.tax,
            serviceCharge: bill.serviceCharge,
            discount: bill.discount,
            items: bill.items.map(itemDTO(from:)),
            participants: participants.map(participantDTO(from:)),
            roomState: roomState
        )
    }
}
