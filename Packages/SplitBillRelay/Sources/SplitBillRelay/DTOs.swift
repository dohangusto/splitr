import Foundation
import SplitBillCore

/// Wire contract for App Clip claiming. `SplitBillRelay` is to the HTTP
/// mailbox what `SplitBillSync` is to CloudKit: it maps Core domain types to
/// and from transport bytes and nothing more. Every payload here is plain
/// JSON — the relay server stores and forwards these, it never interprets
/// them (no bill math, no claim resolution; see the server package).
///
/// Invariants baked into these shapes:
/// - Money is `Int` rupiah on the wire, everywhere. No floating point.
/// - Rates ride as Core's `Rate` (exact `Int` basis points) so the clip can
///   run `SettlementCalculator` locally with no precision loss.
/// - A `participantId` is a temporary, relay-scoped string. It is *not* a
///   CloudKit `Member` id: the host mints the real `Member` (and its UUID)
///   when it drains a participant. The relay is never an identity authority.

// MARK: - Snapshot (host → clip)

/// One bill's worth of claimable state, as the clip sees it. Carries exactly
/// the inputs `SettlementCalculator.settle(bill:...)` needs so the clip can
/// compute each member's share locally without any settlement endpoint.
public struct SnapshotDTO: Codable, Sendable, Hashable {
    public let sessionId: String
    public let merchantName: String
    public let taxRate: Rate
    public let serviceChargeRate: Rate
    public let taxBasis: TaxBasis
    public let items: [ItemDTO]
    public let participants: [ParticipantDTO]
    public let roomState: RoomState

    public init(
        sessionId: String,
        merchantName: String,
        taxRate: Rate,
        serviceChargeRate: Rate,
        taxBasis: TaxBasis,
        items: [ItemDTO],
        participants: [ParticipantDTO],
        roomState: RoomState
    ) {
        self.sessionId = sessionId
        self.merchantName = merchantName
        self.taxRate = taxRate
        self.serviceChargeRate = serviceChargeRate
        self.taxBasis = taxBasis
        self.items = items
        self.participants = participants
        self.roomState = roomState
    }
}

/// One claimable unit. `id` is the Core `BillItem` UUID as a string.
public struct ItemDTO: Codable, Sendable, Hashable {
    public let id: String
    public let name: String
    /// Whole rupiah. Never floating point.
    public let unitPrice: Int
    public let claimState: ClaimStateDTO

    public init(id: String, name: String, unitPrice: Int, claimState: ClaimStateDTO) {
        self.id = id
        self.name = name
        self.unitPrice = unitPrice
        self.claimState = claimState
    }
}

/// Losslessly encodes Core's `ClaimState`. `participantId`s are the holders'
/// relay-scoped strings; `portions` is parallel to `participantIds` and
/// carries Core's exact `Fraction` per claim so shared splits survive intact.
public enum ClaimStateDTO: Codable, Sendable, Hashable {
    case unclaimed
    case claimed(participantIds: [String], portions: [Fraction])
    case forceAssigned(participantId: String)

    private enum Kind: String, Codable {
        case unclaimed, claimed, forceAssigned
    }

    private enum CodingKeys: String, CodingKey {
        case kind, participantIds, portions, participantId
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .unclaimed:
            self = .unclaimed
        case .claimed:
            let ids = try container.decode([String].self, forKey: .participantIds)
            let portions = try container.decode([Fraction].self, forKey: .portions)
            self = .claimed(participantIds: ids, portions: portions)
        case .forceAssigned:
            self = .forceAssigned(participantId: try container.decode(String.self, forKey: .participantId))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .unclaimed:
            try container.encode(Kind.unclaimed, forKey: .kind)
        case .claimed(let ids, let portions):
            try container.encode(Kind.claimed, forKey: .kind)
            try container.encode(ids, forKey: .participantIds)
            try container.encode(portions, forKey: .portions)
        case .forceAssigned(let participantId):
            try container.encode(Kind.forceAssigned, forKey: .kind)
            try container.encode(participantId, forKey: .participantId)
        }
    }
}

/// A member as the clip needs to render them: id + name + emoji. Payment
/// status and host-ness are deliberately absent — claiming doesn't need them.
public struct ParticipantDTO: Codable, Sendable, Hashable {
    public let participantId: String
    public let displayName: String
    public let avatarEmoji: String

    public init(participantId: String, displayName: String, avatarEmoji: String) {
        self.participantId = participantId
        self.displayName = displayName
        self.avatarEmoji = avatarEmoji
    }
}

// MARK: - Claim op (clip → host, via the relay queue)

/// A single toggle from the clip. Shared items are join/leave only: the clip
/// never sends a portion — Core computes the equal split on `joinClaim`, which
/// matches "a member only ever toggles themselves in or out".
public struct ClaimOpDTO: Codable, Sendable, Hashable {
    public let opId: String
    public let participantId: String
    public let itemId: String
    public let action: Action

    public enum Action: String, Codable, Sendable {
        case join
        case leave
    }

    public init(opId: String, participantId: String, itemId: String, action: Action) {
        self.opId = opId
        self.participantId = participantId
        self.itemId = itemId
        self.action = action
    }
}

/// The outcome of one op after the host applied it through the same
/// `RoomStore` claim intent an installed member uses. A `conflict` is a real
/// CloudKit CAS loss (`serverRecordChanged`): `winnerParticipantId` is who
/// holds it now and `updatedClaimState` is the authoritative post-race state.
public struct ClaimResultDTO: Codable, Sendable, Hashable {
    public let opId: String
    public let status: Status
    /// Present only on `.conflict`: the participant/member that won the race.
    public let winnerParticipantId: String?
    /// Authoritative claim state after the host applied (or rejected) the op.
    public let updatedClaimState: ClaimStateDTO

    public enum Status: String, Codable, Sendable {
        case accepted
        case conflict
    }

    public init(
        opId: String,
        status: Status,
        winnerParticipantId: String? = nil,
        updatedClaimState: ClaimStateDTO
    ) {
        self.opId = opId
        self.status = status
        self.winnerParticipantId = winnerParticipantId
        self.updatedClaimState = updatedClaimState
    }
}

// MARK: - Small request/response envelopes

/// Body for `registerParticipant`; the relay assigns the temp id.
public struct RegisterParticipantRequest: Codable, Sendable, Hashable {
    public let displayName: String
    public let avatarEmoji: String

    public init(displayName: String, avatarEmoji: String) {
        self.displayName = displayName
        self.avatarEmoji = avatarEmoji
    }
}

public struct RegisterParticipantResponse: Codable, Sendable, Hashable {
    public let participantId: String

    public init(participantId: String) {
        self.participantId = participantId
    }
}

/// Returned once from `openSession`. `hostToken` never leaves the host app.
public struct OpenSessionResponse: Codable, Sendable, Hashable {
    public let sessionToken: String
    public let hostToken: String

    public init(sessionToken: String, hostToken: String) {
        self.sessionToken = sessionToken
        self.hostToken = hostToken
    }
}
