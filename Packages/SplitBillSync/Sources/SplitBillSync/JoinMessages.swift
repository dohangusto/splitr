import Foundation

/// The joiner's chosen identity — display name + emoji, per CLAUDE.md.
/// Never an Apple ID.
public struct JoinRequest: Codable, Sendable, Equatable {
    public let displayName: String
    public let avatarEmoji: String

    public init(displayName: String, avatarEmoji: String) {
        self.displayName = displayName
        self.avatarEmoji = avatarEmoji
    }
}

/// The host's response after the tap-to-join gesture fires: everything the
/// joiner needs to enter the room through the normal CloudKit path.
public struct JoinInvitation: Codable, Sendable, Equatable {
    public let roomID: UUID
    public let roomName: String
    /// The CKShare invite URL (same one the manual link path uses).
    public let shareURL: URL
    /// Host-assigned member identity — the joiner acts as this member.
    public let memberID: UUID

    public init(roomID: UUID, roomName: String, shareURL: URL, memberID: UUID) {
        self.roomID = roomID
        self.roomName = roomName
        self.shareURL = shareURL
        self.memberID = memberID
    }
}

/// The complete vocabulary of the MPC onboarding channel. Three message
/// kinds and nothing else — this is not a state channel; room state and
/// claims flow exclusively through CloudKit.
public enum JoinMessage: Codable, Sendable, Equatable {
    /// NI discovery token (NSKeyedArchiver-encoded NIDiscoveryToken).
    case discoveryToken(Data)
    /// Joiner → host: who wants to join.
    case joinRequest(JoinRequest)
    /// Host → joiner: the CKShare URL + assigned member UUID.
    case invitation(JoinInvitation)

    public func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }

    public static func decoded(from data: Data) throws -> JoinMessage {
        try JSONDecoder().decode(JoinMessage.self, from: data)
    }
}
