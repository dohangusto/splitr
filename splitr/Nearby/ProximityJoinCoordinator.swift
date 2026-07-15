import Foundation
import Observation
import SplitBillCore
import SplitBillSync

/// Drives the proximity join flow on both sides. Onboarding only: the MPC
/// channel carries token exchange, the joiner's identity, and the host's
/// invitation (CKShare URL + assigned member UUID) — after that, everything
/// flows through CloudKit exactly as a link-based join would.
///
/// Lifetimes (the Milestone 5 fix-pass rule): the host's MPC advertiser
/// lives for the whole "Add People Nearby" session and serves any number
/// of joiners; each joiner gets their own NI ranging session + detector,
/// torn down individually on join or disconnect. Stopping one peer's NI
/// session never touches the advertiser or other peers.
@MainActor
@Observable
final class ProximityJoinCoordinator {

    enum Timeouts {
        /// How long the joiner searches before giving up on finding a host.
        static let discovery: TimeInterval = 30
    }

    enum FailureReason: Equatable {
        case noUWB
        case permissionDenied
        case hostNotFound
        case timeout
        case transport(String)

        var message: String {
            switch self {
            case .noUWB:
                "This iPhone can't measure precise distance (no UWB chip). Use the invite link instead."
            case .permissionDenied:
                "Nearby Interaction permission was declined. Allow it in Settings, or use the invite link."
            case .hostNotFound:
                "No host found nearby. Make sure the host has 'Add People Nearby' open, or use the invite link."
            case .timeout:
                "That took too long. Try again, or use the invite link."
            case .transport(let detail):
                "\(detail) You can always use the invite link instead."
            }
        }
    }

    enum Phase: Equatable {
        case idle
        case searching
        case connecting(peerName: String)
        /// NI is ranging; progress 0...1 drives the ring (host: max across peers).
        case ranging(progress: Double)
        /// Joiner: share accepted, waiting for CloudKit to deliver the room.
        case finishingJoin
        /// Joiner only — the host stays in searching/ranging for the next peer.
        case joined(roomName: String)
        case failed(FailureReason)
    }

    private(set) var phase: Phase = .idle
    private(set) var connectedPeerName: String?
    /// Host: members successfully invited this session (UI list).
    private(set) var joinedNames: [String] = []
    /// Increments once per gesture fire — drives haptics.
    private(set) var gestureFires = 0

    private let store: CloudKitRoomStore
    private let transport: any ProximityTransport
    private let rangingProvider: any ProximityRanging

    private var eventTask: Task<Void, Never>?
    private var watchdogTask: Task<Void, Never>?

    /// One per connected peer (host may have several at once).
    @MainActor
    private final class PeerContext {
        let peer: PeerID
        var session: (any RangingSession)?
        var detector = TapToJoinDetector()
        var rangingTask: Task<Void, Never>?
        var request: JoinRequest?
        var progress: Double = 0
        var invited = false

        init(peer: PeerID) {
            self.peer = peer
        }

        func stopRanging() {
            rangingTask?.cancel()
            rangingTask = nil
            session?.stop()
            session = nil
            progress = 0
        }
    }

    private var peers: [PeerID: PeerContext] = [:]

    // Role context.
    private var hostRoom: (id: UUID, name: String)?
    private var joinerIdentity: JoinRequest?

    var isHost: Bool { hostRoom != nil }

    init(
        store: CloudKitRoomStore,
        transport: (any ProximityTransport)? = nil,
        ranging: (any ProximityRanging)? = nil
    ) {
        self.store = store
        self.transport = transport ?? MultipeerTransport()
        self.rangingProvider = ranging ?? NearbyRanging()
    }

    // MARK: - Entry points

    /// Host: advertise this room continuously; serves joiners one after
    /// another (or several at once) without ever restarting the advertiser.
    func startHosting(roomID: UUID, roomName: String, hostDisplayName: String) {
        guard rangingProvider.isSupported else {
            phase = .failed(.noUWB)
            return
        }
        hostRoom = (roomID, roomName)
        begin(displayName: hostDisplayName, hosting: true)
    }

    /// Joiner: browse for a nearby host with the chosen identity.
    func startJoining(displayName: String, avatarEmoji: String) {
        guard rangingProvider.isSupported else {
            phase = .failed(.noUWB)
            return
        }
        joinerIdentity = JoinRequest(displayName: displayName, avatarEmoji: avatarEmoji)
        begin(displayName: displayName, hosting: false)
        watchdogTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Timeouts.discovery))
            guard let self, !Task.isCancelled else { return }
            if case .searching = phase {
                fail(.hostNotFound)
            }
        }
    }

    func stop() {
        eventTask?.cancel()
        watchdogTask?.cancel()
        for context in peers.values {
            context.stopRanging()
        }
        peers = [:]
        transport.stop()
        phase = .idle
        connectedPeerName = nil
        joinedNames = []
        hostRoom = nil
        joinerIdentity = nil
    }

    // MARK: - Flow

    private func begin(displayName: String, hosting: Bool) {
        phase = .searching
        if hosting {
            transport.startHosting(displayName: displayName)
        } else {
            transport.startBrowsing(displayName: displayName)
        }
        eventTask = Task { [weak self] in
            guard let self else { return }
            for await event in transport.events {
                if Task.isCancelled { return }
                handle(event)
            }
        }
    }

    private func handle(_ event: TransportEvent) {
        switch event {
        case .foundHost(let peer):
            // Joiner auto-connects to the first host found: the deliberate
            // part of joining is the physical gesture, not picking a list.
            if !isHost, case .searching = phase {
                phase = .connecting(peerName: peer.displayName)
                transport.connect(to: peer)
            }

        case .lostHost:
            break

        case .connected(let peer):
            let context = PeerContext(peer: peer)
            peers[peer] = context
            connectedPeerName = peer.displayName
            onConnected(context)

        case .disconnected(let peer):
            guard let context = peers.removeValue(forKey: peer) else { return }
            // Tear down THIS peer's ranging only; the advertiser and any
            // other connected peers keep going untouched.
            context.stopRanging()
            if isHost {
                refreshHostPhase()
            } else {
                connectedPeerName = nil
                switch phase {
                case .joined, .finishingJoin, .idle, .failed:
                    break // expected teardown
                default:
                    fail(.transport("Lost the connection to the host."))
                }
            }

        case .received(let message, let peer):
            guard let context = peers[peer] else { return }
            handle(message, context: context)

        case .failed(let detail):
            // Transport-level failure (couldn't advertise/browse at all).
            fail(.transport(detail))
        }
    }

    private func onConnected(_ context: PeerContext) {
        phase = .connecting(peerName: context.peer.displayName)
        do {
            let session = try rangingProvider.makeSession()
            context.session = session
            transport.send(.discoveryToken(try session.localTokenData()), to: context.peer)
        } catch {
            // This peer can't range; drop them, keep everything else alive.
            peers[context.peer] = nil
            if !isHost {
                fail(.transport("Couldn't start Nearby ranging."))
            } else {
                refreshHostPhase()
            }
            return
        }
        if let joinerIdentity {
            transport.send(.joinRequest(joinerIdentity), to: context.peer)
        }
    }

    private func handle(_ message: JoinMessage, context: PeerContext) {
        switch message {
        case .discoveryToken(let tokenData):
            do {
                try context.session?.startRanging(peerTokenData: tokenData)
                startRangingLoop(context)
                refreshPhaseAfterRangingStart(context)
            } catch {
                context.stopRanging()
                if !isHost {
                    fail(.transport("Couldn't start Nearby ranging."))
                }
            }

        case .joinRequest(let request):
            guard isHost else { return }
            context.request = request

        case .invitation(let invitation):
            guard !isHost else { return }
            completeJoin(with: invitation)
        }
    }

    private func startRangingLoop(_ context: PeerContext) {
        guard let session = context.session else { return }
        context.rangingTask = Task { [weak self, weak context] in
            for await event in session.events {
                guard let self, let context, !Task.isCancelled else { return }
                switch event {
                case .distance(let meters):
                    handleDistance(meters, context: context)
                case .ended(.permissionDenied):
                    fail(.permissionDenied) // our own NI permission: global
                case .ended(.invalidated(let detail)):
                    context.stopRanging()
                    if isHost {
                        refreshHostPhase()
                    } else if case .ranging = phase {
                        fail(.transport(detail))
                    }
                }
            }
        }
    }

    private func handleDistance(_ meters: Double, context: PeerContext) {
        let output = context.detector.process(
            distance: meters,
            at: Date().timeIntervalSinceReferenceDate
        )
        context.progress = output.progress
        if isHost {
            refreshHostPhase()
        } else {
            phase = .ranging(progress: output.progress)
        }
        if output.didFire {
            gestureFires += 1
            if isHost {
                sendInvitation(to: context)
            }
            // Joiner side: haptic fires; the invitation arrives from the host.
        }
    }

    /// Host, when a peer completes the gesture: assign their identity,
    /// write the member record, hand over the invitation — then release
    /// only that peer's ranging. Other peers keep ranging; whoever taps
    /// next gets the next invitation.
    private func sendInvitation(to context: PeerContext) {
        guard let hostRoom, let request = context.request, !context.invited else { return }
        context.invited = true
        context.stopRanging()
        refreshHostPhase()
        Task {
            guard let url = await store.inviteURL(roomID: hostRoom.id) else {
                context.invited = false
                fail(.transport("Couldn't create the room invitation."))
                return
            }
            let member = Member(
                id: UUID(),
                displayName: request.displayName,
                avatarEmoji: request.avatarEmoji
            )
            store.addMember(member, roomID: hostRoom.id)
            transport.send(
                .invitation(JoinInvitation(
                    roomID: hostRoom.id,
                    roomName: hostRoom.name,
                    shareURL: url,
                    memberID: member.id
                )),
                to: context.peer
            )
            joinedNames.append("\(request.avatarEmoji) \(request.displayName)")
        }
    }

    /// Joiner, on receiving the invitation: accept the share through the
    /// Milestone 4 path, wait for CloudKit to sync the room in, and act as
    /// the host-assigned member from now on.
    private func completeJoin(with invitation: JoinInvitation) {
        phase = .finishingJoin
        for context in peers.values {
            context.stopRanging()
        }
        Task {
            guard await store.acceptShare(from: invitation.shareURL) else {
                fail(.transport("Couldn't accept the room invitation."))
                return
            }
            guard await store.waitForRoom(id: invitation.roomID) else {
                fail(.timeout)
                return
            }
            store.setActingMember(invitation.memberID, in: invitation.roomID)
            transport.stop()
            phase = .joined(roomName: invitation.roomName)
        }
    }

    /// Host phase = the most advanced of the live peers; searching when idle.
    private func refreshHostPhase() {
        if case .failed = phase { return }
        let ranging = peers.values.filter { $0.rangingTask != nil }
        if let best = ranging.max(by: { $0.progress < $1.progress }) {
            connectedPeerName = best.peer.displayName
            phase = .ranging(progress: best.progress)
        } else if let waiting = peers.values.first(where: { !$0.invited }) {
            connectedPeerName = waiting.peer.displayName
            phase = .connecting(peerName: waiting.peer.displayName)
        } else {
            connectedPeerName = nil
            phase = .searching
        }
    }

    private func refreshPhaseAfterRangingStart(_ context: PeerContext) {
        if isHost {
            refreshHostPhase()
        } else {
            phase = .ranging(progress: 0)
        }
    }

    private func fail(_ reason: FailureReason) {
        for context in peers.values {
            context.stopRanging()
        }
        phase = .failed(reason)
    }
}
