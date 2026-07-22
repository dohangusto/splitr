import SwiftUI
import SplitBillCore

struct HomePageView: View {
    let store: any RoomStoring

    @State private var showCreateRoom = false
    @State private var showJoinNearby = false
    @State private var showProfile = false
    @State private var isCheckingHosting = false
    @State private var hostingIssue: String?
    @State private var profile = UserProfile.load()
    
    @State private var showScanFlow = false
    @State private var activeScanRoomID: UUID?
    
    @State private var selectedTab: HomeTab = .home
    
    @State private var searchText = ""
    @State private var roomsPath: [UUID] = []
    @State private var historyPath: [UUID] = []
    @State private var searchPath: [UUID] = []

    private enum HomeTab: Hashable {
        case home
        case history
        case search
    }

    private var activeRooms: [Room] {
        store.rooms.filter { $0.state != .closed }
    }
    
    private var closedRooms: [Room] {
        store.rooms.filter { $0.state == .closed }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Home", systemImage: "house", value: HomeTab.home) {
                homeTab
            }

            Tab("History", systemImage: "clock", value: HomeTab.history) {
                historyTab
            }

            // Adaptive tab bar treatment used by system apps.
            Tab(value: HomeTab.search, role: .search) {
                searchTab
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabBarMinimizeBehavior(.onScrollDown)
        .sheet(isPresented: $showCreateRoom) {
            CreateRoomView(store: store)
        }
        .sheet(isPresented: $showJoinNearby) {
            NearbyJoinView(store: store) { roomID in
                roomsPath.append(roomID)
            }
        }
        .sheet(isPresented: $showScanFlow) {
            if let roomID = activeScanRoomID {
                ReceiptScanFlow(store: store, roomID: roomID)
            }
        }
        .onChange(of: showScanFlow) { oldValue, newValue in
            if !newValue, let roomID = activeScanRoomID {
                // Creating a room always lands the host in that room's detail —
                // never back on Home — even if they skipped or cancelled the
                // scan. (Bills can still be added from the detail surface.)
                if store.room(withID: roomID) != nil {
                    roomsPath.append(roomID)
                }
                activeScanRoomID = nil
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
    }

    // MARK: - Subviews

    // Home Tab View
    private var homeTab: some View {
        NavigationStack(path: $roomsPath) {
            ZStack {
                // Background layout gradient
                LinearGradient(
                    gradient: Gradient(colors: [Color("PrimaryBackground"), .white.opacity(0.2)]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 24) {
                        headerSection
                        actionCardsSection
                        openTransactionsSection
                    }
                    .padding(.vertical, 16)
                }
            }
            .navigationBarHidden(true)
            .navigationDestination(for: UUID.self) { roomID in
                RoomRootView(store: store, roomID: roomID)
            }
            .navigationDestination(isPresented: $showProfile) {
                ProfileView(profile: $profile) {
                    store.resetAllData()
                    profile = UserProfile.load()
                }
            }
        }
    }

    // History Tab View
    private var historyTab: some View {
        NavigationStack(path: $historyPath) {
            ZStack {
                LinearGradient(
                    gradient: Gradient(colors: [Color("PrimaryBackground"), .white.opacity(0.2)]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                
                VStack(alignment: .leading, spacing: 20) {
                    historyHeader
                    
                    if closedRooms.isEmpty {
                        Spacer()
                        historyEmptyState
                        Spacer()
                    } else {
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(spacing: 16) {
                                ForEach(closedRooms) { room in
                                    NavigationLink(value: room.id) {
                                        HistoryTransactionCard(
                                            roomName: room.name,
                                            membersCount: room.members.count,
                                            billsCount: room.bills.count,
                                            statusLabel: actionLabel(for: room)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 24)
                        }
                    }
                }
                .padding(.vertical, 16)
                
            }
            .navigationBarHidden(true)
            .navigationDestination(for: UUID.self) { roomID in
                RoomRootView(store: store, roomID: roomID)
            }
        }
    }
    
    // Centered placeholder shown when there are no closed rooms.
    private var historyEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)

            Text("No completed transactions yet.")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
    
    private var historyHeader: some View {
        Text("History")
            .font(.largeTitle)
            .bold()
            .foregroundColor(.black)
            .padding(.horizontal, 24)
    }

    // Search Tab View
    private var searchTab: some View {
        NavigationStack(path: $searchPath) {
            ZStack {
                LinearGradient(
                    gradient: Gradient(colors: [Color("PrimaryBackground"), .white.opacity(0.2)]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                let searchResults = store.rooms.filter {
                    searchText.isEmpty ? true : $0.name.localizedCaseInsensitiveContains(searchText)
                }
                
                VStack(alignment: .leading, spacing: 20) {
                    searchHeader
                    
                    if searchResults.isEmpty {
                        Text("No rooms found.")
                            .font(.headline)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(spacing: 16) {
                                ForEach(searchResults) { room in
                                    NavigationLink(value: room.id) {
                                        searchResultCard(for: room)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 24)
                        }
                    }
                }
                .padding(.vertical, 16)
            }
            
            .navigationBarHidden(true)
            .searchable(text: $searchText, prompt: "Room name")
            .navigationDestination(for: UUID.self) { roomID in
                RoomRootView(store: store, roomID: roomID)
            }
        }
    }
    
    // Centered placeholder shown when there are no any transactions.
    private var searchEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)

            Text("No rooms found.")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
    
    private var searchHeader: some View {
        Text("Search")
            .font(.largeTitle)
            .bold()
            .foregroundColor(.black)
            .padding(.horizontal, 24)
    }
    
    /// Picks the right visual for one search result: `TransactionRow`
    /// and `HistoryTransactionCard`
    @ViewBuilder
    private func searchResultCard(for room: Room) -> some View {
        if room.state == .closed {
            HistoryTransactionCard(
                roomName: room.name,
                membersCount: room.members.count,
                billsCount: room.bills.count,
                statusLabel: actionLabel(for: room)
            )
        } else {
            TransactionRow(
                roomName: room.name,
                membersCount: room.members.count,
                billsCount: room.bills.count,
                actionLabel: actionLabel(for: room)
            )
            .background(Color.white)
            .cornerRadius(24)
            .shadow(color: Color.black.opacity(0.04), radius: 10, x: 0, y: 5)
        }
    }
    
    // Header Section -> Title and Profile
    private var headerSection: some View {
        HStack {
            Text("Split Air")
                .font(.largeTitle)
                .bold()
                .foregroundColor(.black)
            
            Spacer()
            
            Button(action: { showProfile = true }) {
                Image(profile.avatar)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 24)
    }
    
    // Action Cards to Scan a Bill or Join a Room
    private var actionCardsSection: some View {
        HStack(spacing: 16) {
            ActionCard(
                title: "Start a Split",
                description: "Create a bill and invite your friends.",
                iconName: "camera.fill",
                accentColor: Color("SplitAirBlue"),
                iconTintColor: Color("SplitAirBlue"),
                action: createRoomTapped
            )
            .disabled(isCheckingHosting)
            
            ActionCard(
                title: "Join Split Room",
                description: "Find nearby friends automatically.",
                iconName: "link",
                accentColor: Color("SplitAirGreen"),
                iconTintColor: Color("SecondaryGreen"),
                action: joinRoomTapped
            )
        }
        .padding(.horizontal, 24)
    }

    // List of Open Transactions
    private var openTransactionsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Open Transactions")
                    .font(.headline)
                    .bold()
                    .foregroundColor(.black)
                
                Text("Review and complete your unpaid bills.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            
            if activeRooms.isEmpty {
                VStack(spacing: 16) {
                    Image("EmptyTransaction")
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 220)
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
            } else {
                VStack(spacing: 0) {
                    ForEach(activeRooms) { room in
                        NavigationLink(value: room.id) {
                            TransactionRow(
                                roomName: room.name,
                                membersCount: room.members.count,
                                billsCount: room.bills.count,
                                actionLabel: actionLabel(for: room)
                            )
                        }
                        
                        if room.id != activeRooms.last?.id {
                            Divider()
                                .padding(.leading, 76)
                                .padding(.trailing, 20)
                        }
                    }
                }
                .padding(.bottom, 12)
            }
        }
        .background(Color.white)
        .cornerRadius(24)
        .shadow(color: Color.black.opacity(0.04), radius: 10, x: 0, y: 5)
        .padding(.horizontal, 24)
    }

    // MARK: - Actions & Helpers

    private func actionLabel(for room: Room) -> String {
        switch room.state {
        case .open: return "Start Claiming"
        case .claiming, .settling: return "Claimed"
        case .closed: return "Closed"
        }
    }

    private func createRoomTapped() {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .none
        let dateString = dateFormatter.string(from: Date())
        let defaultRoomName = "Bill \(dateString)"
        
        let profile = UserProfile.load()
        let hostName = profile.name.isEmpty ? "Host" : profile.name
        let hostEmoji = profile.avatar
        
        guard let cloudStore = AppComposition.cloudStore else {
            let newRoom = store.createRoom(
                named: defaultRoomName,
                hostName: hostName,
                hostEmoji: hostEmoji
            )
            activeScanRoomID = newRoom.id
            showScanFlow = true
            return
        }
        isCheckingHosting = true
        Task {
            let issue = await cloudStore.hostingIssueMessage()
            isCheckingHosting = false
            if let issue {
                hostingIssue = issue
            } else {
                let newRoom = store.createRoom(
                    named: defaultRoomName,
                    hostName: hostName,
                    hostEmoji: hostEmoji
                )
                activeScanRoomID = newRoom.id
                showScanFlow = true
            }
        }
    }

    private func joinRoomTapped() {
        #if targetEnvironment(simulator)
        store.alert = StoreAlert(
            message: "Joining a room needs a physical iPhone. On the simulator, explore the demo rooms instead."
        )
        #else
        showJoinNearby = true
        #endif
    }
}

// MARK: - Previews

#Preview("Home Screen Layout") {
    HomePageView(store: MockRoomStore(rooms: MockData.rooms()))
}
