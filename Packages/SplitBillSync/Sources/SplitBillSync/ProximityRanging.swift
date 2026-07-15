import Foundation

public enum RangingEvent: Sendable, Equatable {
    /// Distance to the peer in meters.
    case distance(Double)
    /// The session ended and will produce no more samples.
    case ended(RangingEndReason)
}

public enum RangingEndReason: Sendable, Equatable {
    case permissionDenied
    case invalidated(String)
}

/// Factory for per-peer ranging sessions. NearbyInteraction requires one
/// NISession per peer, and the host ranges several joiners concurrently —
/// so ranging lifetime is per peer, never global. Stopping one peer's
/// session must not affect any other peer or the MPC transport.
public protocol ProximityRanging: AnyObject, Sendable {
    /// Whether this device can measure precise distance (UWB chip + user
    /// permission possible). Check before offering the proximity gesture;
    /// degrade to the manual invite link when false.
    var isSupported: Bool { get }
    /// Creates an independent ranging session for one peer.
    func makeSession() throws -> any RangingSession
}

/// One peer's ranging lifetime: token exchange → run → distance events → stop.
public protocol RangingSession: AnyObject, Sendable {
    /// This session's NI discovery token, encoded for the MPC channel.
    func localTokenData() throws -> Data
    /// Starts ranging against the peer's encoded discovery token.
    func startRanging(peerTokenData: Data) throws
    func stop()
    var events: AsyncStream<RangingEvent> { get }
}

public enum RangingError: Error {
    case unsupportedDevice
    case invalidPeerToken
}
