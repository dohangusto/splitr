import SwiftUI
import SplitBillCore

/// Home: active rooms plus a collapsed history of closed rooms.
struct RoomListView: View {
    let store: any RoomStoring

    @State private var showCreateRoom = false
    @State private var showHistory = false

    private var activeRooms: [Room] { store.rooms.filter { $0.state != .closed } }
    private var closedRooms: [Room] { store.rooms.filter { $0.state == .closed } }

    var body: some View {
        NavigationStack {
            Group {
                if store.rooms.isEmpty {
                    ContentUnavailableView {
                        Label("No rooms yet", systemImage: "person.3")
                    } description: {
                        Text("Create a room, scan the receipt, and let everyone claim their own items.")
                    } actions: {
                        Button("Create Room") { showCreateRoom = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        Section {
                            ForEach(activeRooms) { room in
                                NavigationLink(value: room.id) {
                                    RoomRow(room: room)
                                }
                            }
                        } header: {
                            if !activeRooms.isEmpty { Text("Active") }
                        }
                        if !closedRooms.isEmpty {
                            Section {
                                DisclosureGroup(isExpanded: $showHistory) {
                                    ForEach(closedRooms) { room in
                                        NavigationLink(value: room.id) {
                                            RoomRow(room: room)
                                        }
                                    }
                                } label: {
                                    Label("History (\(closedRooms.count))", systemImage: "archivebox")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("splitr")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Create Room", systemImage: "plus") {
                        showCreateRoom = true
                    }
                }
            }
            .navigationDestination(for: UUID.self) { roomID in
                RoomDetailView(store: store, roomID: roomID)
            }
            .sheet(isPresented: $showCreateRoom) {
                CreateRoomView(store: store)
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
    }
}

private struct RoomRow: View {
    let room: Room

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(room.name)
                    .font(.headline)
                Text("\(room.members.count) members · \(room.bills.count) bills")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            RoomStateBadge(state: room.state)
        }
    }
}

struct RoomStateBadge: View {
    let state: RoomState

    var body: some View {
        Text(label)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: .capsule)
            .foregroundStyle(color)
    }

    private var label: String {
        switch state {
        case .open: "Open"
        case .claiming: "Claiming"
        case .settling: "Settling"
        case .closed: "Closed"
        }
    }

    private var color: Color {
        switch state {
        case .open: .blue
        case .claiming: .orange
        case .settling: .purple
        case .closed: .gray
        }
    }
}
