import Foundation
import MultipeerConnectivity

/// MultipeerConnectivity implementation of `ProximityTransport`.
///
/// Service type `splitr-join` — Info.plist must declare Bonjour services
/// `_splitr-join._tcp` and `_splitr-join._udp` plus a local-network usage
/// description. Encryption is required; invitations time out after
/// `Timeouts.connect` seconds.
public final class MultipeerTransport: NSObject, ProximityTransport, @unchecked Sendable {

    public enum Timeouts {
        /// How long a joiner's session invitation may sit unanswered.
        public static let connect: TimeInterval = 15
    }

    private static let serviceType = "splitr-join"

    public let events: AsyncStream<TransportEvent>
    private let continuation: AsyncStream<TransportEvent>.Continuation

    /// Guards all mutable MPC state — delegate callbacks arrive on
    /// arbitrary internal queues.
    private let lock = NSLock()
    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var localPeer: MCPeerID?
    private var foundPeers: [PeerID: MCPeerID] = [:]

    public override init() {
        (events, continuation) = AsyncStream.makeStream(of: TransportEvent.self)
        super.init()
    }

    // MARK: - ProximityTransport

    public func startHosting(displayName: String) {
        lock.withLock {
            teardownLocked()
            let peer = MCPeerID(displayName: displayName)
            localPeer = peer
            session = makeSession(peer: peer)
            let advertiser = MCNearbyServiceAdvertiser(
                peer: peer,
                discoveryInfo: nil,
                serviceType: Self.serviceType
            )
            advertiser.delegate = self
            advertiser.startAdvertisingPeer()
            self.advertiser = advertiser
        }
    }

    public func startBrowsing(displayName: String) {
        lock.withLock {
            teardownLocked()
            let peer = MCPeerID(displayName: displayName)
            localPeer = peer
            session = makeSession(peer: peer)
            let browser = MCNearbyServiceBrowser(peer: peer, serviceType: Self.serviceType)
            browser.delegate = self
            browser.startBrowsingForPeers()
            self.browser = browser
        }
    }

    public func connect(to host: PeerID) {
        lock.withLock {
            guard let session, let mcPeer = foundPeers[host] else { return }
            browser?.invitePeer(mcPeer, to: session, withContext: nil, timeout: Timeouts.connect)
        }
    }

    public func send(_ message: JoinMessage, to peer: PeerID) {
        let result: Result<Void, Error> = lock.withLock {
            guard let session else {
                return .failure(MCError(.notConnected))
            }
            guard let mcPeer = session.connectedPeers.first(where: { $0.displayName == peer.displayName }) else {
                return .failure(MCError(.notConnected))
            }
            return Result {
                try session.send(try message.encoded(), toPeers: [mcPeer], with: .reliable)
            }
        }
        if case .failure(let error) = result {
            continuation.yield(.failed("Couldn't reach \(peer.displayName): \(error.localizedDescription)"))
        }
    }

    public func stop() {
        lock.withLock { teardownLocked() }
    }

    // MARK: - Private

    private func makeSession(peer: MCPeerID) -> MCSession {
        let session = MCSession(peer: peer, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        return session
    }

    private func teardownLocked() {
        advertiser?.stopAdvertisingPeer()
        advertiser = nil
        browser?.stopBrowsingForPeers()
        browser = nil
        session?.disconnect()
        session = nil
        foundPeers = [:]
        localPeer = nil
    }
}

// MARK: - MCSessionDelegate

extension MultipeerTransport: MCSessionDelegate {
    public func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        let peer = PeerID(displayName: peerID.displayName)
        switch state {
        case .connected:
            continuation.yield(.connected(peer))
        case .notConnected:
            continuation.yield(.disconnected(peer))
        case .connecting:
            break
        @unknown default:
            break
        }
    }

    public func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let message = try? JoinMessage.decoded(from: data) else {
            // Not one of our three message kinds — the channel carries
            // nothing else, so unknown data is dropped.
            return
        }
        continuation.yield(.received(message, from: PeerID(displayName: peerID.displayName)))
    }

    public func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    public func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    public func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

// MARK: - MCNearbyServiceAdvertiserDelegate (host)

extension MultipeerTransport: MCNearbyServiceAdvertiserDelegate {
    public func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer peerID: MCPeerID,
        withContext context: Data?,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        // The host accepts anyone who found the service; the deliberate
        // part of joining is the NI proximity gesture, not the MPC handshake.
        let session = lock.withLock { self.session }
        invitationHandler(session != nil, session)
    }

    public func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        continuation.yield(.failed("Couldn't start hosting: \(error.localizedDescription)"))
    }
}

// MARK: - MCNearbyServiceBrowserDelegate (joiner)

extension MultipeerTransport: MCNearbyServiceBrowserDelegate {
    public func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        let peer = PeerID(displayName: peerID.displayName)
        lock.withLock { foundPeers[peer] = peerID }
        continuation.yield(.foundHost(peer))
    }

    public func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        let peer = PeerID(displayName: peerID.displayName)
        lock.withLock { foundPeers[peer] = nil }
        continuation.yield(.lostHost(peer))
    }

    public func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        continuation.yield(.failed("Couldn't search for nearby hosts: \(error.localizedDescription)"))
    }
}

private struct MCError: Error, LocalizedError {
    enum Kind { case notConnected }
    let kind: Kind
    init(_ kind: Kind) { self.kind = kind }
    var errorDescription: String? { "Not connected" }
}
