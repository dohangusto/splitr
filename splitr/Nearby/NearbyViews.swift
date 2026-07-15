import SwiftUI
import SplitBillSync

/// The proximity ring: tightens and fills as the devices approach and the
/// dwell progresses. Progress 1 = gesture fired.
struct ProximityRingView: View {
    let progress: Double
    let active: Bool

    var body: some View {
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: 10)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    progress >= 1 ? Color.green : Color.accentColor,
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.1), value: progress)
            Image(systemName: progress >= 1 ? "checkmark" : "iphone.radiowaves.left.and.right")
                .font(.system(size: 40))
                .foregroundStyle(progress >= 1 ? .green : active ? Color.accentColor : .secondary)
                .symbolEffect(.pulse, isActive: active && progress < 1)
        }
        .frame(width: 140, height: 140)
        .padding()
    }
}

/// Shared status layout for both sides of the proximity join flow.
private struct ProximityPhaseView: View {
    let phase: ProximityJoinCoordinator.Phase
    let waitingText: String
    let onRetry: () -> Void
    let onUseLink: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            switch phase {
            case .idle, .searching:
                ProximityRingView(progress: 0, active: false)
                Text(waitingText)
                    .font(.headline)
                ProgressView()

            case .connecting(let peerName):
                ProximityRingView(progress: 0, active: true)
                Text("Found \(peerName)")
                    .font(.headline)
                Text("Connecting…")
                    .foregroundStyle(.secondary)

            case .ranging(let progress):
                ProximityRingView(progress: progress, active: true)
                Text("Bring the iPhones close together")
                    .font(.headline)
                // The UWB antenna is directional: face-to-face ranges best.
                Text("Point your iPhone at your friend's and hold them near each other until the ring fills.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

            case .finishingJoin:
                ProximityRingView(progress: 1, active: true)
                Text("Joining the room…")
                    .font(.headline)
                ProgressView()

            case .joined(let roomName):
                ProximityRingView(progress: 1, active: false)
                Text("You're in \(roomName)!")
                    .font(.headline)

            case .failed(let reason):
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 44))
                    .foregroundStyle(.orange)
                    .padding()
                Text(reason.message)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                Button("Try Again", action: onRetry)
                    .buttonStyle(.borderedProminent)
                if let onUseLink {
                    Button("Use Invite Link Instead", action: onUseLink)
                }
            }
        }
        .padding()
    }
}

/// Host side: "Add People Nearby". Advertises the room; a live ring shows
/// the approach of the joiner; on gesture fire the invitation is handed over.
struct NearbyHostView: View {
    let store: CloudKitRoomStore
    let roomID: UUID
    let roomName: String
    let hostDisplayName: String
    /// Fallback: dismiss and open the manual invite-link sheet.
    var onUseLink: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var coordinator: ProximityJoinCoordinator?

    var body: some View {
        NavigationStack {
            VStack {
                if let coordinator {
                    ProximityPhaseView(
                        phase: coordinator.phase,
                        waitingText: "Waiting for a friend's iPhone…",
                        onRetry: { restart(coordinator) },
                        onUseLink: onUseLink.map { useLink in
                            { dismiss(); useLink() }
                        }
                    )
                    if let peer = coordinator.connectedPeerName,
                       case .ranging = coordinator.phase {
                        Text("\(peer) is here — bring the phones together, screens facing each other.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    // One session serves everyone: the list grows as each
                    // friend taps in, no restart needed between joiners.
                    if !coordinator.joinedNames.isEmpty {
                        VStack(spacing: 4) {
                            Text("Joined this session")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            ForEach(coordinator.joinedNames, id: \.self) { name in
                                Text(name)
                            }
                        }
                        .padding(.top, 8)
                    }
                }
            }
            .navigationTitle("Add People Nearby")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sensoryFeedback(.success, trigger: coordinator?.gestureFires ?? 0)
            .onAppear {
                let coordinator = ProximityJoinCoordinator(store: store)
                self.coordinator = coordinator
                coordinator.startHosting(
                    roomID: roomID,
                    roomName: roomName,
                    hostDisplayName: hostDisplayName
                )
            }
            .onDisappear { coordinator?.stop() }
        }
    }

    private func restart(_ coordinator: ProximityJoinCoordinator) {
        coordinator.stop()
        coordinator.startHosting(roomID: roomID, roomName: roomName, hostDisplayName: hostDisplayName)
    }
}

/// Joiner side: pick a name + emoji, then the proximity gesture.
struct NearbyJoinView: View {
    let store: CloudKitRoomStore

    @Environment(\.dismiss) private var dismiss
    @State private var coordinator: ProximityJoinCoordinator?
    @State private var name = ""
    @State private var emoji = "🙂"
    @State private var started = false

    var body: some View {
        NavigationStack {
            Group {
                if let coordinator, started {
                    VStack {
                        ProximityPhaseView(
                            phase: coordinator.phase,
                            waitingText: "Looking for a host nearby…",
                            onRetry: {
                                coordinator.stop()
                                coordinator.startJoining(displayName: name, avatarEmoji: emoji)
                            },
                            onUseLink: nil // joiner fallback: host sends the link
                        )
                        if case .joined = coordinator.phase {
                            Button("Open the Room") { dismiss() }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                } else {
                    Form {
                        Section("You") {
                            TextField("Display name", text: $name)
                            EmojiPicker(selection: $emoji)
                        }
                        Section {
                            Button {
                                start()
                            } label: {
                                Label("Find the Host", systemImage: "iphone.radiowaves.left.and.right")
                            }
                            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                        } footer: {
                            Text("Then bring your iPhone close to the host's iPhone to join.")
                        }
                    }
                }
            }
            .navigationTitle("Join Nearby")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sensoryFeedback(.success, trigger: coordinator?.gestureFires ?? 0)
            .onDisappear { coordinator?.stop() }
        }
    }

    private func start() {
        let coordinator = ProximityJoinCoordinator(store: store)
        self.coordinator = coordinator
        started = true
        coordinator.startJoining(
            displayName: name.trimmingCharacters(in: .whitespaces),
            avatarEmoji: emoji
        )
    }
}
