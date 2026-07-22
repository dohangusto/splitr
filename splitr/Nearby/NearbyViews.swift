import SwiftUI
import SplitBillCore
import SplitBillSync

/// Host side: "Add People Nearby", drawn as a radar — the host's avatar at
/// the center of concentric range rings, each successfully invited friend
/// popping onto a ring as their own avatar bubble. One advertising session
/// serves every joiner in turn; the radar just keeps filling.
struct NearbyHostView: View {
    let store: any RoomStoring
    let roomID: UUID
    let roomName: String
    let hostDisplayName: String
    /// Fallback: dismiss and open the manual invite-link sheet.
    var onUseLink: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var coordinator: ProximityJoinCoordinator?

    private var hostEmoji: String {
        let room = store.room(withID: roomID)
        return room?.member(withID: room?.hostMemberID ?? UUID())?.avatarEmoji ?? "🙂"
    }

    var body: some View {
        ZStack {
            NearbyBackground()

            VStack(spacing: 0) {
                header
                    .padding(.top, 8)

                Spacer(minLength: 12)

                if let coordinator {
                    statusText(coordinator.phase)
                        .padding(.horizontal, 32)

                    Spacer(minLength: 12)

                    if case .failed = coordinator.phase {
                        failureActions(coordinator)
                    } else {
                        NearbyRadarView(
                            centerEmoji: hostEmoji,
                            friends: coordinator.joinedFriends,
                            rangingProgress: rangingProgress(coordinator.phase),
                            incomingPeerName: incomingPeerName(coordinator),
                            onTapIncomingPeer: {
                                if let name = incomingPeerName(coordinator) {
                                    coordinator.forceJoin(peerName: name)
                                }
                            }
                        )
                        .padding(.horizontal, 12)
                    }

                    Spacer(minLength: 12)

                    footer(joinedCount: coordinator.joinedFriends.count)
                }
            }
            .sensoryFeedback(.success, trigger: coordinator?.gestureFires ?? 0)
        }
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

    private var header: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .background(.background, in: .circle)
                    .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
            }
            .accessibilityLabel("Back")
            Spacer()
        }
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private func statusText(_ phase: ProximityJoinCoordinator.Phase) -> some View {
        VStack(spacing: 6) {
            switch phase {
            case .idle, .searching, .joined:
                Text("Looking nearby…").font(.headline)
                Text("Your friends will appear here in a moment.")
                    .font(.subheadline).foregroundStyle(.secondary)
            case .connecting(let peerName):
                Text("Found \(peerName)").font(.headline)
                Text("Connecting…")
                    .font(.subheadline).foregroundStyle(.secondary)
            case .ranging:
                Text("Bring the iPhones close together").font(.headline)
                // The UWB antenna is directional: face-to-face ranges best.
                Text("Hold them near each other until the circle fills.")
                    .font(.subheadline).foregroundStyle(.secondary)
            case .finishingJoin:
                Text("Almost in…").font(.headline)
            case .failed(let reason):
                Text("Couldn't add people nearby").font(.headline)
                Text(reason.message)
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .multilineTextAlignment(.center)
    }

    private func failureActions(_ coordinator: ProximityJoinCoordinator) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 44))
                .foregroundStyle(.orange)
                .padding(.bottom, 8)
            Button {
                coordinator.stop()
                coordinator.startHosting(roomID: roomID, roomName: roomName, hostDisplayName: hostDisplayName)
            } label: {
                Label("Try Again", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            if let onUseLink {
                Button {
                    dismiss()
                    onUseLink()
                } label: {
                    Label("Use Invite Link", systemImage: "link")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal, 40)
    }

    private func footer(joinedCount: Int) -> some View {
        VStack(spacing: 16) {
            Text(joinedCount == 0
                ? "No Friends Joined Yet"
                : "^[\(joinedCount) Friend](inflect: true) Joined")
                .font(.title3.weight(.semibold))
                .contentTransition(.numericText())
                .animation(.snappy, value: joinedCount)
            Button {
                dismiss()
            } label: {
                Text("Continue")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
    }

    private func rangingProgress(_ phase: ProximityJoinCoordinator.Phase) -> Double? {
        if case .ranging(let progress) = phase { return progress }
        return nil
    }

    /// The peer currently connecting/ranging — shown as a faded bubble on
    /// the outer ring until their join completes.
    private func incomingPeerName(_ coordinator: ProximityJoinCoordinator) -> String? {
        switch coordinator.phase {
        case .connecting(let peerName): peerName
        case .ranging: coordinator.connectedPeerName
        default: nil
        }
    }
}

// MARK: - Radar

/// Soft top-to-bottom wash behind the radar screen.
private struct NearbyBackground: View {
    var body: some View {
        LinearGradient(
            colors: [Color.accentColor.opacity(0.18), Color.accentColor.opacity(0.04)],
            startPoint: .top,
            endPoint: .bottom
        )
        .background(Color(.systemBackground))
        .ignoresSafeArea()
    }
}

/// Concentric range rings with the host at the center and each joined
/// friend as an avatar bubble on a ring. Purely presentational.
private struct NearbyRadarView: View {
    let centerEmoji: String
    let friends: [ProximityJoinCoordinator.JoinedFriend]
    /// Non-nil while NI is ranging a joiner; fills the circle around the host.
    let rangingProgress: Double?
    /// Peer connecting/ranging right now, not yet joined.
    let incomingPeerName: String?
    var onTapIncomingPeer: (() -> Void)? = nil

    @State private var pulse1 = false
    @State private var pulse2 = false
    @State private var rotationAngle: Double = 0
    @State private var isIcon1Active = true

    /// Fixed slots so bubbles never jump when new friends arrive:
    /// (angle in degrees, radius as a fraction of the outer ring).
    private static let slots: [(angle: Double, radius: Double)] = [
        (-70, 0.66), (170, 0.95), (25, 0.63), (205, 0.68), (65, 0.92),
        (140, 0.60), (-15, 0.94), (250, 0.93), (100, 0.65), (-45, 0.96),
    ]

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let outerRadius = side / 2 - 30
            let centerSize = side * 0.24

            ZStack {
                ForEach([0.36, 0.68, 1.0], id: \.self) { scale in
                    Circle()
                        .stroke(Color.accentColor.opacity(0.25), lineWidth: 1)
                        .frame(width: outerRadius * 2 * scale, height: outerRadius * 2 * scale)
                        .position(center)
                }

                // Glowing radar circular sweep/shine ring
                Circle()
                    .stroke(
                        AngularGradient(
                            colors: [
                                Color.accentColor,
                                Color.accentColor.opacity(0.4),
                                Color.accentColor.opacity(0.1),
                                Color.clear,
                                Color.accentColor.opacity(0.1),
                                Color.accentColor.opacity(0.4),
                                Color.accentColor
                            ],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .frame(width: centerSize + 16, height: centerSize + 16)
                    .rotationEffect(.degrees(rotationAngle))
                    .position(center)
                    .shadow(color: Color.accentColor.opacity(0.4), radius: 3)

                // Pulses breathing outward (gentler and slower)
                Circle()
                    .stroke(Color.accentColor.opacity(pulse1 ? 0 : 0.25), lineWidth: 1.5)
                    .frame(width: centerSize, height: centerSize)
                    .scaleEffect(pulse1 ? 1.8 : 1.0)
                    .position(center)
                    .animation(.easeOut(duration: 3.0).repeatForever(autoreverses: false), value: pulse1)

                Circle()
                    .stroke(Color.accentColor.opacity(pulse2 ? 0 : 0.2), lineWidth: 1.0)
                    .frame(width: centerSize, height: centerSize)
                    .scaleEffect(pulse2 ? 1.4 : 1.0)
                    .position(center)
                    .animation(.easeOut(duration: 3.0).repeatForever(autoreverses: false).delay(1.0), value: pulse2)

                // Host at the center; the ranging dwell fills the outline.
                ZStack {
                    Circle()
                        .stroke(Color.accentColor.opacity(0.3), lineWidth: 1.5)
                    if let rangingProgress {
                        Circle()
                            .trim(from: 0, to: rangingProgress)
                            .stroke(
                                rangingProgress >= 1 ? Color.green : Color.accentColor,
                                style: StrokeStyle(lineWidth: 3, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                            .animation(.linear(duration: 0.1), value: rangingProgress)
                    }
                    
                    // Natural blinking eye logo (Icon2 = open, Icon1 = closed)
                    ZStack {
                        Image("Icon1")
                            .resizable()
                            .scaledToFit()
                            .padding(centerSize * 0.18)
                            .opacity(isIcon1Active ? 1.0 : 0.0)
                        
                        Image("Icon2")
                            .resizable()
                            .scaledToFit()
                            .padding(centerSize * 0.18)
                            .opacity(isIcon1Active ? 0.0 : 1.0)
                    }
                }
                .frame(width: centerSize, height: centerSize)
                .position(center)

                ForEach(Array(friends.enumerated()), id: \.element.id) { index, friend in
                    let slot = Self.slots[index % Self.slots.count]
                    AvatarBubble(emoji: friend.emoji, name: friend.name, size: side * 0.155)
                        .position(position(slot: slot, center: center, outerRadius: outerRadius))
                        .transition(.scale.combined(with: .opacity))
                }

                // The friend mid-handshake fades in on the outer ring.
                if let incomingPeerName {
                    AvatarBubble(emoji: "📡", name: incomingPeerName, size: side * 0.155)
                        .opacity(0.55)
                        .position(position(
                            slot: Self.slots[friends.count % Self.slots.count],
                            center: center,
                            outerRadius: outerRadius
                        ))
                        .contentShape(Circle())
                        .onTapGesture {
                            onTapIncomingPeer?()
                        }
                }
            }
            .animation(.bouncy, value: friends)
        }
        .aspectRatio(1, contentMode: .fit)
        .onAppear {
            pulse1 = true
            pulse2 = true
            isIcon1Active = false // Start with open eye (Icon2)
            withAnimation(.linear(duration: 6).repeatForever(autoreverses: false)) {
                rotationAngle = 360
            }
            Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { _ in
                withAnimation(.easeInOut(duration: 0.12)) {
                    isIcon1Active = true // close eye (Icon1)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                    withAnimation(.easeInOut(duration: 0.12)) {
                        isIcon1Active = false // open eye (Icon2)
                    }
                }
            }
        }
    }

    private func position(
        slot: (angle: Double, radius: Double),
        center: CGPoint,
        outerRadius: CGFloat
    ) -> CGPoint {
        let radians = slot.angle * .pi / 180
        return CGPoint(
            x: center.x + cos(radians) * outerRadius * slot.radius,
            y: center.y + sin(radians) * outerRadius * slot.radius
        )
    }
}

/// One friend on the radar: emoji avatar in a white bubble, name underneath.
private struct AvatarBubble: View {
    let emoji: String
    let name: String
    let size: CGFloat

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                Circle()
                    .fill(.background)
                    .shadow(color: .black.opacity(0.12), radius: 5, y: 2)
                Group {
                    if let uiImage = UIImage(named: emoji) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Text(emoji)
                            .font(.system(size: size * 0.52))
                    }
                }
                .frame(width: size, height: size)
                .clipShape(Circle())
            }
            .frame(width: size, height: size)
            Text(name)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: size * 1.6)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name) joined")
    }
}

/// Joiner side: pick a name + emoji, then the proximity gesture.
/// The invite link is the standing fallback: reachable from the form for
/// non-UWB devices, and offered on every proximity failure state.
struct NearbyJoinView: View {
    let store: any RoomStoring
    var onJoined: ((UUID) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var coordinator: ProximityJoinCoordinator?
    @State private var profile = UserProfile.load()
    @State private var started = false
    @State private var showLinkEntry = false

    var body: some View {
        Group {
            if let coordinator, started {
                joinRadar(coordinator)
            } else {
                entryForm
            }
        }
        .sheet(isPresented: $showLinkEntry) {
            JoinViaLinkView(store: store)
        }
        .sensoryFeedback(.success, trigger: coordinator?.gestureFires ?? 0)
        .onChange(of: coordinator?.phase) { _, newPhase in
            if case .joined = newPhase, let roomID = coordinator?.joinedRoomID {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    onJoined?(roomID)
                    dismiss()
                }
            }
        }
        .onAppear {
            let nameTrimmed = profile.name.trimmingCharacters(in: .whitespaces)
            if !nameTrimmed.isEmpty {
                start()
            }
        }
        .onDisappear { coordinator?.stop() }
    }

    // MARK: Entry form (name + profile photo before searching)

    private var entryForm: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 16) {
                        Image(profile.avatar)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 60, height: 60)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color(.systemGray5), lineWidth: 1))
                        
                        VStack(alignment: .leading, spacing: 4) {
                            TextField("Display name", text: $profile.name)
                                .font(.headline)
                            Text("Profile Photo")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("You")
                } footer: {
                    Text("Tap Find the Host below, then bring your iPhone close to the host's iPhone to join. If your friend sent a link in Messages, just tap it there — it opens splitr directly.")
                }
            }
            .navigationTitle("Join Nearby")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Join with an Invite Link", systemImage: "link") {
                        showLinkEntry = true
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Find the Host") {
                        profile.save()
                        start()
                    }
                    .disabled(profile.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    // MARK: Radar (searching → ranging → joined)

    private func joinRadar(_ coordinator: ProximityJoinCoordinator) -> some View {
        ZStack {
            NearbyBackground()

            VStack(spacing: 0) {
                HStack {
                    Button {
                        // Back to the name form, not out of the sheet —
                        // stops the session cleanly either way.
                        coordinator.stop()
                        started = false
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 44, height: 44)
                            .background(.background, in: .circle)
                            .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
                    }
                    .accessibilityLabel("Back")
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                Spacer(minLength: 12)

                joinStatusText(coordinator.phase)
                    .padding(.horizontal, 32)

                Spacer(minLength: 12)

                if case .failed = coordinator.phase {
                    joinFailureActions(coordinator)
                } else {
                    NearbyRadarView(
                        centerEmoji: profile.avatar,
                        friends: [],
                        rangingProgress: {
                            if case .ranging(let progress) = coordinator.phase { return progress }
                            return nil
                        }(),
                        incomingPeerName: {
                            switch coordinator.phase {
                            case .connecting(let peerName): peerName
                            case .ranging: coordinator.connectedPeerName
                            default: nil
                            }
                        }()
                    )
                    .padding(.horizontal, 12)
                }

                Spacer(minLength: 12)

                if case .joined = coordinator.phase {
                    Button {
                        dismiss()
                    } label: {
                        Text("Open the Room")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)
                }
            }
        }
    }

    @ViewBuilder
    private func joinStatusText(_ phase: ProximityJoinCoordinator.Phase) -> some View {
        VStack(spacing: 6) {
            switch phase {
            case .idle, .searching:
                Text("Looking for the host…").font(.headline)
                Text("Move close to your friend's iPhone.")
                    .font(.subheadline).foregroundStyle(.secondary)
            case .connecting(let peerName):
                Text("Found \(peerName)").font(.headline)
                Text("Connecting…")
                    .font(.subheadline).foregroundStyle(.secondary)
            case .ranging:
                Text("Bring the iPhones close together").font(.headline)
                // The UWB antenna is directional: face-to-face ranges best.
                Text("Hold them near each other until the circle fills.")
                    .font(.subheadline).foregroundStyle(.secondary)
            case .finishingJoin:
                Text("Joining the room…").font(.headline)
                ProgressView()
            case .joined(let roomName):
                Text("You're in \(roomName)!").font(.headline)
                Text("Claim your items once the host starts claiming.")
                    .font(.subheadline).foregroundStyle(.secondary)
            case .failed(let reason):
                Text("Couldn't join nearby").font(.headline)
                Text(reason.message)
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .multilineTextAlignment(.center)
    }

    private func joinFailureActions(_ coordinator: ProximityJoinCoordinator) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 44))
                .foregroundStyle(.orange)
                .padding(.bottom, 8)
            Button {
                coordinator.stop()
                coordinator.startJoining(
                    displayName: profile.name.trimmingCharacters(in: .whitespaces),
                    avatarEmoji: profile.avatar
                )
            } label: {
                Label("Try Again", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            if AppComposition.cloudStore != nil {
                Button {
                    coordinator.stop()
                    showLinkEntry = true
                } label: {
                    Label("Use Invite Link", systemImage: "link")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal, 40)
    }

    private func start() {
        let trimmedName = profile.name.trimmingCharacters(in: .whitespaces)
        let coordinator = ProximityJoinCoordinator(store: store)
        self.coordinator = coordinator
        started = true
        coordinator.startJoining(
            displayName: trimmedName,
            avatarEmoji: profile.avatar
        )
    }
}

/// Manual invite-link entry: the escape hatch for non-UWB devices and for
/// any proximity failure. Accepting the pasted CKShare URL goes through the
/// exact same path as tapping the link in Messages.
struct JoinViaLinkView: View {
    let store: any RoomStoring

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
