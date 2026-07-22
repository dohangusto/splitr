import SplitBillRelay
import Vapor

/// Let Vapor decode/encode the shared wire DTOs directly. They are already
/// `Codable & Sendable`, so `Content` conformance is free. Reusing the exact
/// `SplitBillRelay` types (rather than re-declaring them here) keeps a single
/// source of truth for the wire contract — the server can't drift from the
/// client. Retroactive because the types and `Content` live in other modules.
extension SnapshotDTO: @retroactive Content {}
extension ItemDTO: @retroactive Content {}
extension ParticipantDTO: @retroactive Content {}
extension ClaimOpDTO: @retroactive Content {}
extension ClaimResultDTO: @retroactive Content {}
extension RegisterParticipantRequest: @retroactive Content {}
extension RegisterParticipantResponse: @retroactive Content {}
extension OpenSessionResponse: @retroactive Content {}
