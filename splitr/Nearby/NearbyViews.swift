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
/// Pure content layer: it only *shows* the phase — retry/fallback actions
/// live in the presenting screen's toolbar.
private struct ProximityPhaseView: View {
    let phase: ProximityJoinCoordinator.Phase
    let waitingText: String

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
                        waitingText: "Waiting for a friend's iPhone…"
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
                // Failure recovery lives in the tools layer, not the content.
                if let coordinator, case .failed = coordinator.phase {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        if let onUseLink {
                            Button("Use Invite Link", systemImage: "link") {
                                dismiss()
                                onUseLink()
                            }
                        }
                        Button("Try Again", systemImage: "arrow.clockwise") {
                            restart(coordinator)
                        }
                    }
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
/// The invite link is the standing fallback: reachable from the form for
/// non-UWB devices, and offered on every proximity failure state.
struct NearbyJoinView: View {
    let store: CloudKitRoomStore

    @Environment(\.dismiss) private var dismiss
    @State private var coordinator: ProximityJoinCoordinator?
    @State private var name = UserDefaults.standard.string(forKey: "splitr.user_display_name") ?? ""
    @State private var emoji = UserDefaults.standard.string(forKey: "splitr.user_avatar_emoji") ?? "🙂"
    @State private var started = false
    @State private var showLinkEntry = false

    var body: some View {
        NavigationStack {
            Group {
                if let coordinator, started {
                    ProximityPhaseView(
                        phase: coordinator.phase,
                        waitingText: "Looking for a host nearby…"
                    )
                } else {
                    Form {
                        Section {
                            TextField("Display name", text: $name)
                            EmojiPicker(selection: $emoji)
                        } header: {
                            Text("You")
                        } footer: {
                            Text("Tap Find the Host below, then bring your iPhone close to the host's iPhone to join. If your friend sent a link in Messages, just tap it there — it opens splitr directly.")
                        }
                    }
                }
            }
            .navigationTitle("Join Nearby")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { joinToolbar }
            .sheet(isPresented: $showLinkEntry) {
                JoinViaLinkView(store: store)
            }
            .sensoryFeedback(.success, trigger: coordinator?.gestureFires ?? 0)
            .onDisappear { coordinator?.stop() }
        }
    }

    /// Phase-dependent actions in the top toolbar: find/retry/fallback while
    /// joining, the confirm once joined. Content below only shows status.
    @ToolbarContentBuilder
    private var joinToolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
        }
        if let coordinator, started {
            switch coordinator.phase {
            case .failed:
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Use Invite Link", systemImage: "link") {
                        coordinator.stop()
                        showLinkEntry = true
                    }
                    Button("Try Again", systemImage: "arrow.clockwise") {
                        coordinator.stop()
                        coordinator.startJoining(displayName: name, avatarEmoji: emoji)
                    }
                }
            case .joined:
                ToolbarItem(placement: .confirmationAction) {
                    Button("Open the Room") {
                        dismiss()
                    }
                }
            default:
                // Searching/ranging: nothing to act on; Cancel is enough.
                ToolbarItem(placement: .automatic) { EmptyView() }
            }
        } else {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Join with an Invite Link", systemImage: "link") {
                    showLinkEntry = true
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Find the Host") {
                    start()
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func start() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        UserDefaults.standard.set(trimmedName, forKey: "splitr.user_display_name")
        UserDefaults.standard.set(emoji, forKey: "splitr.user_avatar_emoji")

        let coordinator = ProximityJoinCoordinator(store: store)
        self.coordinator = coordinator
        started = true
        coordinator.startJoining(
            displayName: trimmedName,
            avatarEmoji: emoji
        )
    }
}

/// Manual invite-link entry: the escape hatch for non-UWB devices and for
/// any proximity failure. Accepting the pasted CKShare URL goes through the
/// exact same path as tapping the link in Messages.
struct JoinViaLinkView: View {
    let store: CloudKitRoomStore

    @Environment(\.dismiss) private var dismiss
    @State private var linkText = ""
    @State private var isJoining = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Paste the invite link", text: $linkText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                } footer: {
                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    } else {
                        Text("Ask the host to send the room's invite link (it starts with icloud.com), then paste it here.")
                    }
                }
            }
            .navigationTitle("Join via Link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isJoining)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isJoining {
                        ProgressView()
                    } else {
                        Button("Join") { join() }
                            .disabled(linkText.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
        .presentationDetents([.medium])
        .interactiveDismissDisabled(isJoining)
    }

    private func join() {
        let trimmed = linkText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.host() != nil else {
            errorMessage = "That doesn't look like a link. Paste the full invite link from the host."
            return
        }
        errorMessage = nil
        isJoining = true
        Task {
            let joined = await store.acceptShare(from: url)
            isJoining = false
            if joined {
                dismiss()
            } else {
                // acceptShare also raises the store alert; keep the inline
                // copy here so the failure is visible without leaving the sheet.
                errorMessage = "Couldn't join with that link. Ask the host for a fresh one."
            }
        }
    }
}
