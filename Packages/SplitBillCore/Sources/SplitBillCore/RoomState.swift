/// Lifecycle of a room. Forward path is `open → claiming → settling → closed`;
/// the single allowed rollback is `settling → claiming`. `closed` is terminal.
/// Only the host may drive transitions.
public enum RoomState: String, Sendable, Hashable, Codable, CaseIterable {
    case open
    case claiming
    case settling
    case closed
}
