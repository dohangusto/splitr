import Foundation

/// A nearby peer, identified by its advertised display name.
/// (Wraps MCPeerID in the real transport; plain value for mocks/tests.)
public struct PeerID: Hashable, Sendable {
    public let displayName: String

    public init(displayName: String) {
        self.displayName = displayName
    }
}

public enum TransportEvent: Sendable, Equatable {
    case foundHost(PeerID)
    case lostHost(PeerID)
    case connected(PeerID)
    case disconnected(PeerID)
    case received(JoinMessage, from: PeerID)
    case failed(String)
}

/// The onboarding-only peer-to-peer channel. Carries exactly the three
/// `JoinMessage` kinds during proximity join, then is torn down — it never
/// carries room state or claims.
///
/// Roles: the host advertises (rooms in `open`/`claiming` accept joiners);
/// joiners browse and `connect(to:)` a discovered host.
public protocol ProximityTransport: AnyObject, Sendable {
    var events: AsyncStream<TransportEvent> { get }

    /// Host side: advertise this device for joining.
    func startHosting(displayName: String)
    /// Joiner side: look for advertising hosts.
    func startBrowsing(displayName: String)
    /// Joiner side: invite a discovered host into the session.
    func connect(to host: PeerID)
    /// Failures surface as `.failed` events rather than throws so mocks
    /// and the UI handle both directions the same way.
    func send(_ message: JoinMessage, to peer: PeerID)
    /// Tears everything down (both roles). Safe to call repeatedly.
    func stop()
}
