import CloudKit
import Foundation

/// CloudKit record types and field keys — the schema contract with the
/// CloudKit Console. One room = one custom zone in the host's private
/// database; the zone is the unit that gets shared via CKShare.
public enum RecordSchema {
    public static let containerIdentifier = "iCloud.com.c4.splitr"
    /// Custom zone name for a room: "room-<uuid>".
    public static func zoneName(roomID: UUID) -> String {
        "room-\(roomID.uuidString)"
    }

    public static func roomID(fromZoneName name: String) -> UUID? {
        guard name.hasPrefix("room-") else { return nil }
        return UUID(uuidString: String(name.dropFirst("room-".count)))
    }

    public enum RoomType {
        public static let name = "Room"
        public static let roomName = "name"
        public static let state = "state"
        public static let hostMemberID = "hostMemberID"
        public static let createdAt = "roomCreatedAt"
    }

    public enum MemberType {
        public static let name = "Member"
        public static let displayName = "displayName"
        public static let avatarEmoji = "avatarEmoji"
        public static let isHost = "isHost"
        public static let paymentStatus = "paymentStatus"
        public static let sortIndex = "sortIndex"
        public static let roomRef = "roomRef"
    }

    public enum BillType {
        public static let name = "Bill"
        public static let merchantName = "merchantName"
        public static let photoReference = "photoReference"
        public static let taxRateBasisPoints = "taxRateBasisPoints"
        public static let serviceRateBasisPoints = "serviceRateBasisPoints"
        public static let taxBasis = "taxBasis"
        public static let createdAt = "billCreatedAt"
        public static let sortIndex = "sortIndex"
        public static let roomRef = "roomRef"
    }

    public enum ItemType {
        public static let name = "BillItem"
        public static let itemName = "itemName"
        public static let unitPrice = "unitPrice"
        public static let claimKind = "claimKind"
        /// Parallel arrays encoding claims (memberIDs + portion fractions).
        /// For `forceAssigned`, `claimMemberIDs` holds the single assignee.
        public static let claimMemberIDs = "claimMemberIDs"
        public static let claimNumerators = "claimNumerators"
        public static let claimDenominators = "claimDenominators"
        public static let sortIndex = "sortIndex"
        public static let billRef = "billRef"
    }

    public enum ClaimKind {
        public static let unclaimed = "unclaimed"
        public static let claimed = "claimed"
        public static let forceAssigned = "forceAssigned"
    }
}
