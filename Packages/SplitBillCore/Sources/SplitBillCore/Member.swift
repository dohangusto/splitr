import Foundation

/// How far along a member is in paying the host back.
/// Both sides must check off: member says "I've paid", host says "received".
public enum PaymentStatus: String, Sendable, Hashable, Codable, CaseIterable {
    case none
    case memberMarkedPaid
    case hostConfirmed
}

/// A participant in a room. Identity is a display name + emoji chosen at join
/// time with a host-assigned unique ID — never derived from Apple ID.
public struct Member: Identifiable, Sendable, Hashable, Codable {
    public let id: UUID
    public var displayName: String
    public var avatarEmoji: String
    public var isHost: Bool
    public var paymentStatus: PaymentStatus

    public init(
        id: UUID = UUID(),
        displayName: String,
        avatarEmoji: String,
        isHost: Bool = false,
        paymentStatus: PaymentStatus = .none
    ) {
        self.id = id
        self.displayName = displayName
        self.avatarEmoji = avatarEmoji
        self.isHost = isHost
        self.paymentStatus = paymentStatus
    }
}
