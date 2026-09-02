import SwiftUI
import SplitBillCore

struct RoomListView: View {
    let store: any RoomStoring

    @State private var showCreateRoom = false
    @State private var showJoinNearby = false
    @State private var showProfile = false
    @State private var isCheckingHosting = false
    @State private var hostingIssue: String?
    @State private var profile = UserProfile.load()

    // Per-tab navigation paths: the bottom accessory is Home-scoped, so it
    // must disappear the moment any stack leaves its root.
    @State private var roomsPath: [UUID] = []
    @State private var historyPath: [UUID] = []

    private var activeRooms: [Room] { store.rooms.filter { $0.state != .closed } }
    private var closedRooms: [Room] { store.rooms.filter { $0.state == .closed } }

    private var isAtRoot: Bool {
        roomsPath.isEmpty && historyPath.isEmpty && !showProfile
    }

    var body: some View {
        // Home-scoped actions: the accessory exists only at the tab roots.
        // Inside a room the room's own toolbar takes over — never both.
        Group {
            if #available(iOS 26.1, *) {
                tabs.tabViewBottomAccessory(isEnabled: isAtRoot) {
                    accessory
                }
            } else {
                tabs.tabViewBottomAccessory {
                    if isAtRoot { accessory }
                }
            }
        }
        .sheet(isPresented: $showCreateRoom) {
            CreateRoomView(store: store)
        }
        .sheet(isPresented: $showJoinNearby) {
            if let cloudStore = AppComposition.cloudStore {
                NearbyJoinView(store: cloudStore)
            }
        }
        .alert(
            "Can't host a room right now",
            isPresented: Binding(
                get: { hostingIssue != nil },
                set: { if !$0 { hostingIssue = nil } }
            ),
            presenting: hostingIssue
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { issue in
            Text(issue)
        }
        .alert(
            "Can't do that",
            isPresented: Binding(
                get: { store.alert != nil },
                set: { if !$0 { store.alert = nil } }
            ),
            presenting: store.alert
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { alert in
            Text(alert.message)
        }
    }

    private var tabs: some View {
        TabView {
            Tab("Rooms", systemImage: "person.3") {
                roomsTab
            }
            Tab("History", systemImage: "archivebox") {
                historyTab
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
    }

    private var accessory: some View {
        JoinCreateAccessory(
            isCheckingHosting: isCheckingHosting,
            onJoin: joinRoomTapped,
            onCreate: createRoomTapped
        )
    }

    // MARK: - Rooms tab

    private var roomsTab: some View {
        NavigationStack(path: $roomsPath) {
            Group {
                if activeRooms.isEmpty && store.isLoadingRooms {
                    loadingState
                } else if activeRooms.isEmpty {
                    emptyState
                } else {
                    List(activeRooms) { room in
                        NavigationLink(value: room.id) {
                            RoomRow(
                                room: room,
                                perspectiveID: store.actingMemberID(in: room.id)
                            )
                        }
                    }
                }
            }
            .navigationTitle("splitr")
            .toolbarTitleDisplayMode(.inlineLarge)
            .toolbar { roomsToolbar }
            .navigationDestination(for: UUID.self) { roomID in
                RoomRootView(store: store, roomID: roomID)
            }
            .navigationDestination(isPresented: $showProfile) {
                ProfileView(profile: $profile)
            }
        }
    }

    /// `.inlineLarge` puts the large-styled title in the same bar row as the
    /// toolbar items (the "Inline Large Title" preview in the Examples), so
    /// the only item needed here is the profile action — an authentic SF
    /// symbol at top-trailing.
    @ToolbarContentBuilder
    private var roomsToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button("Profile", systemImage: "person") {
                showProfile = true
            }
        }
    }

    /// First launch. Content layer only *informs* — the actual actions
    /// (Scan a Receipt, Join Room) live in the floating accessory below,
    /// where Apple maps actions. Both paths get equal billing in the copy,
    /// since for some users joining is the only way in.
    private var emptyState: some View {
        ContentUnavailableView {
            Label("No rooms yet", systemImage: "person.3")
        } description: {
            Text("Scan a receipt to start a bill room, or join a friend who's already hosting — both are right below.")
        }
    }

    /// Initial iCloud fetch in flight: say so, instead of flashing a false
    /// "no rooms" that reads as lost data.
    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text("Getting your rooms…")
                .font(.headline)
            Text("Fetching your bill rooms from iCloud.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - History tab

    private var historyTab: some View {
        NavigationStack(path: $historyPath) {
            Group {
                if closedRooms.isEmpty && store.isLoadingRooms {
                    loadingState
                } else if closedRooms.isEmpty {
                    ContentUnavailableView {
                        Label("No closed rooms yet", systemImage: "archivebox")
                    } description: {
                        Text("Rooms land here once everyone has settled up. They stay read-only.")
                    }
                } else {
                    List(closedRooms) { room in
                        NavigationLink(value: room.id) {
                            RoomRow(
                                room: room,
                                perspectiveID: store.actingMemberID(in: room.id)
                            )
                        }
                    }
                }
            }
            .navigationTitle("History")
            .toolbarTitleDisplayMode(.inlineLarge)
            .navigationDestination(for: UUID.self) { roomID in
                RoomRootView(store: store, roomID: roomID)
            }
        }
    }

    // MARK: - Actions

    /// Hosting preflight before the create flow: quota-full or managed
    /// Apple IDs learn here — with copy pointing at joining — instead of
    /// filling in a room that silently fails later.
    private func createRoomTapped() {
        guard let cloudStore = AppComposition.cloudStore else {
            showCreateRoom = true
            return
        }
        isCheckingHosting = true
        Task {
            let issue = await cloudStore.hostingIssueMessage()
            isCheckingHosting = false
            if let issue {
                hostingIssue = issue
            } else {
                showCreateRoom = true
            }
        }
    }

    private func joinRoomTapped() {
        if AppComposition.cloudStore != nil {
            showJoinNearby = true
        } else {
            store.alert = StoreAlert(
                message: "Joining a room needs a physical iPhone signed into iCloud. On the simulator, explore the demo rooms instead."
            )
        }
    }
}

// MARK: - Bottom accessory

/// The two co-equal primary actions as a persistent accessory above the tab
/// bar (the Music-MiniPlayer slot): Join Room via Nearby Interaction, and
/// Scan a Receipt (= start a new bill room as host). Adapts to the accessory
/// placement: full-width labeled buttons when `.expanded`, compact controls
/// when the minimizing tab bar pulls it `.inline`.
private struct JoinCreateAccessory: View {
    let isCheckingHosting: Bool
    let onJoin: () -> Void
    let onCreate: () -> Void

    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    var body: some View {
        switch placement {
        case .inline:
            HStack {
                Button("Join", systemImage: "iphone.radiowaves.left.and.right", action: onJoin)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Divider()
                    .frame(height: 20)
                Spacer()
                Button("Scan", systemImage: "doc.viewfinder", action: onCreate)
                    .font(.subheadline.weight(.medium))
                    .disabled(isCheckingHosting)
            }
            .labelStyle(.titleAndIcon)
            .padding(.horizontal)

        case .expanded:
            HStack(spacing: 12) {
                Button(action: onJoin) {
                    Label("Join Room", systemImage: "iphone.radiowaves.left.and.right")
                        .frame(maxWidth: .infinity)
                }
                Button(action: onCreate) {
                    Label("New Bill", systemImage: "doc.viewfinder")
                        .frame(maxWidth: .infinity)
                }
                .disabled(isCheckingHosting)
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal)

        default: // placement is optional — nil means undefined
            EmptyView()
        }
    }
}

// MARK: - Row

/// One room, answered from the viewer's perspective: what do I need to do
/// about it? Name plus a single secondary line — the waiting-on-me signal
/// when there is one, otherwise the rupiah number that matters to *me*.
private struct RoomRow: View {
    let room: Room
    let perspectiveID: UUID?

    var body: some View {
        let glance = RoomGlance(room: room, memberID: perspectiveID)
        VStack(alignment: .leading, spacing: 4) {
            Text(room.name)
                .font(.headline)
            if let waiting = glance.waitingOnMe {
                Label(waiting, systemImage: "hand.point.right.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.orange)
            } else {
                Text(glance.headline)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

/// Pure presentation math for a row, derived from Core.
private struct RoomGlance {
    let headline: String
    let waitingOnMe: String?

    init(room: Room, memberID: UUID?) {
        let me = memberID ?? room.hostMemberID
        let isHost = me == room.hostMemberID

        switch room.state {
        case .open:
            headline = "\(room.members.count) members · \(room.bills.count) bills"
            waitingOnMe = isHost && !room.bills.isEmpty
                ? "Start claiming when everyone's in" : nil

        case .claiming:
            let items = room.bills.flatMap(\.items)
            let unclaimed = items.count {
                if case .unclaimed = $0.claimState { return true }
                return false
            }
            if isHost {
                headline = "\(items.count - unclaimed) of \(items.count) items claimed"
                waitingOnMe = unclaimed == 0 && !items.isEmpty
                    ? "All items claimed — ready to settle" : nil
            } else {
                let claimed = Self.claimedSubtotal(room: room, memberID: me)
                headline = claimed > 0
                    ? "You've claimed \(claimed.rupiah) so far"
                    : "You haven't claimed anything yet"
                waitingOnMe = unclaimed > 0
                    ? "\(unclaimed) item\(unclaimed == 1 ? "" : "s") unclaimed — grab yours" : nil
            }

        case .settling:
            guard let settlement = try? SettlementCalculator.settle(room: room) else {
                headline = "Settling up"
                waitingOnMe = nil
                return
            }
            if isHost {
                let owing = room.members.filter {
                    !$0.isHost && $0.paymentStatus != .hostConfirmed
                }
                let outstanding = owing.reduce(0) {
                    $0 + (settlement.settlement(for: $1.id)?.totalOwed ?? 0)
                }
                headline = owing.isEmpty
                    ? "Everyone has paid you back"
                    : "\(outstanding.rupiah) from \(owing.count) \(owing.count == 1 ? "person" : "people")"
                let toConfirm = room.members.count { $0.paymentStatus == .memberMarkedPaid }
                if toConfirm > 0 {
                    waitingOnMe = "\(toConfirm) payment\(toConfirm == 1 ? "" : "s") to confirm"
                } else if owing.isEmpty {
                    waitingOnMe = "All settled — close the room"
                } else {
                    waitingOnMe = nil
                }
            } else {
                let owed = settlement.settlement(for: me)?.totalOwed ?? 0
                switch room.member(withID: me)?.paymentStatus {
                case .memberMarkedPaid, .hostConfirmed:
                    headline = "Settled — you paid \(owed.rupiah)"
                    waitingOnMe = nil
                default:
                    headline = "You owe \(owed.rupiah)"
                    waitingOnMe = "Pay the host, then mark as paid"
                }
            }

        case .closed:
            if let settlement = try? SettlementCalculator.settle(room: room) {
                if isHost {
                    headline = "Settled · \(settlement.grandTotal.rupiah) total"
                } else {
                    let paid = settlement.settlement(for: me)?.totalOwed ?? 0
                    headline = "Settled · you paid \(paid.rupiah)"
                }
            } else {
                headline = "Closed"
            }
            waitingOnMe = nil
        }
    }

    /// A member's running claimed amount while claiming is still open:
    /// portion-weighted item prices, floored to whole rupiah (final tax and
    /// service allocation only exists once claiming closes).
    private static func claimedSubtotal(room: Room, memberID: UUID) -> Int {
        let prices = Dictionary(
            room.bills.flatMap(\.items).map { ($0.id, $0.unitPrice) },
            uniquingKeysWith: { first, _ in first }
        )
        return room.claims(for: memberID)
            .reduce(Fraction.zero) { $0 + $1.portion * (prices[$1.itemID] ?? 0) }
            .flooredValue
    }
}

#Preview("Rooms") {
    RoomListView(store: MockRoomStore(rooms: MockData.rooms()))
}

#Preview("Empty") {
    RoomListView(store: MockRoomStore())
}
