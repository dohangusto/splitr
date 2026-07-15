#if canImport(NearbyInteraction) && os(iOS)
import Foundation
import NearbyInteraction

/// NearbyInteraction implementation of `ProximityRanging` (UWB precise
/// distance). Foreground-only by design — no NI background mode.
/// Each `makeSession()` owns its own `NISession`, so the host can range
/// multiple joiners at once and tear them down independently.
public final class NearbyRanging: ProximityRanging {
    public init() {}

    public var isSupported: Bool {
        NISession.deviceCapabilities.supportsPreciseDistanceMeasurement
    }

    public func makeSession() throws -> any RangingSession {
        guard isSupported else { throw RangingError.unsupportedDevice }
        return NearbyRangingSession()
    }
}

final class NearbyRangingSession: NSObject, RangingSession, @unchecked Sendable {

    public let events: AsyncStream<RangingEvent>
    private let continuation: AsyncStream<RangingEvent>.Continuation

    private let lock = NSLock()
    private var session: NISession?

    override init() {
        (events, continuation) = AsyncStream.makeStream(of: RangingEvent.self)
        super.init()
        let session = NISession()
        session.delegate = self
        self.session = session
    }

    func localTokenData() throws -> Data {
        guard let token = lock.withLock({ session })?.discoveryToken else {
            throw RangingError.unsupportedDevice
        }
        return try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
    }

    func startRanging(peerTokenData: Data) throws {
        guard let peerToken = try? NSKeyedUnarchiver.unarchivedObject(
            ofClass: NIDiscoveryToken.self,
            from: peerTokenData
        ) else {
            throw RangingError.invalidPeerToken
        }
        guard let session = lock.withLock({ self.session }) else {
            throw RangingError.unsupportedDevice
        }
        session.run(NINearbyPeerConfiguration(peerToken: peerToken))
    }

    func stop() {
        lock.withLock {
            session?.invalidate()
            session = nil
        }
        continuation.finish()
    }
}

extension NearbyRangingSession: NISessionDelegate {
    func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        for object in nearbyObjects {
            if let distance = object.distance {
                continuation.yield(.distance(Double(distance)))
            }
        }
    }

    func session(_ session: NISession, didInvalidateWith error: Error) {
        let reason: RangingEndReason
        if let niError = error as? NIError, niError.code == .userDidNotAllow {
            reason = .permissionDenied
        } else {
            reason = .invalidated(error.localizedDescription)
        }
        continuation.yield(.ended(reason))
    }

    func session(
        _ session: NISession,
        didRemove nearbyObjects: [NINearbyObject],
        reason: NINearbyObject.RemovalReason
    ) {
        continuation.yield(.ended(.invalidated("Lost the other device — move closer and try again.")))
    }
}
#endif
