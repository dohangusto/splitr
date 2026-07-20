//
//  DetailView.swift
//  splitr
//

import SwiftUI
import SplitBillCore

/// The host's (penalang's) room surface. Reads the same Room / Bill / claim
/// state the member surface reads; layout follows the team's shell, behavior
/// adapts to the room state. Exception powers live behind the Manage menu.
struct DetailView: View {

    let store: any RoomStoring
    let roomID: UUID

    @State private var showingPeopleList = false
    @State private var showScanReceipt = false
    @State private var showAddBill = false
    @State private var billToEdit: Bill?
    @State private var showAdvanceConfirm = false
    @State private var showRollbackConfirm = false
    @State private var memberToKick: Member?
    @State private var showDeleteConfirm = false

    private var room: Room? { store.room(withID: roomID) }

    var body: some View {
        if let room {
            content(room)
        } else {
            ContentUnavailableView("Room not found", systemImage: "questionmark.circle")
        }
    }

    private func content(_ room: Room) -> some View {
        ZStack {

            // MARK: Background
            Color(
                red: 237/255,
                green: 242/255,
                blue: 255/255
            )
            .ignoresSafeArea()

            // MARK: Content
            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {

                    // Header, with the host's Manage powers tucked trailing.
                    ZStack(alignment: .trailing) {
                        NavigationHeader(title: "Detail")
                        manageMenu(room)
                    }

                    // Split Bill Name — display-only until rename lands
                    // with persistence in milestone 4.
                    SplitBillNameCard(billName: .constant(room.name))
                        .disabled(true)

                    // People
                    PeopleCard(people: room.members.map(\.avatarEmoji)) {
                        showingPeopleList = true
                    }

                    // Bills Photo
                    BillsPhotoCard(
                        photos: room.bills.compactMap { ReceiptPhotoStore.load($0.photoReference) }
                    ) {
                        if canEditBills(room) { showScanReceipt = true }
                    }

                    // Bill Detail — one card per bill, straight from Core.
                    if room.bills.isEmpty, room.state == .open {
                        emptyBillsCard
                    }
                    ForEach(room.bills) { bill in
                        BillDetailCard(
                            bill: bill,
                            canEdit: room.state == .open,
                            onEdit: { billToEdit = bill }
                        )
                    }

                    // Door into the room's working screen for this state.
                    subDestination(room)
                }
                .padding(20)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            pinnedAction(room)
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .tabBar)
        .sheet(isPresented: $showingPeopleList) {
            PeopleListSheet(store: store, roomID: roomID)
        }
        .sheet(isPresented: $showScanReceipt) {
            ReceiptScanFlow(store: store, roomID: roomID)
        }
        .sheet(isPresented: $showAddBill) {
            AddBillView(store: store, roomID: roomID)
        }
        .sheet(item: $billToEdit) { bill in
            NavigationStack {
                AddBillForm(store: store, roomID: roomID, existingBill: bill)
            }
        }
        .confirmationDialog(
            room.state.advanceQuestion,
            isPresented: $showAdvanceConfirm,
            titleVisibility: .visible
        ) {
            Button(room.state.advanceLabel, role: room.state == .settling ? .destructive : nil) {
                store.advance(roomID: roomID)
            }
        } message: {
            Text(room.state.advanceDetail)
        }
        .confirmationDialog(
            "Reopen claiming?",
            isPresented: $showRollbackConfirm,
            titleVisibility: .visible
        ) {
            Button("Back to Claiming") { store.rollbackToClaiming(roomID: roomID) }
        } message: {
            Text("Members will be able to change their claims again. Current settlement amounts will be recomputed.")
        }
        .alert(item: $memberToKick) { member in
            Alert(
                title: Text("Remove \(member.displayName)?"),
                message: Text("All items they claimed — including their share of split items — will return to unclaimed."),
                primaryButton: .destructive(Text("Remove")) {
                    store.kick(memberID: member.id, roomID: roomID)
                },
                secondaryButton: .cancel()
            )
        }
        .alert("Delete this room?", isPresented: $showDeleteConfirm) {
            Button("Delete Room", role: .destructive) { deleteRoom() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(deleteWarning(room))
        }
    }

    // MARK: - Manage (host exception powers, off the main surface)

    /// Contents are state-dependent: rollback only in settling, kick while
    /// the room is live, delete always — a finished room still needs cleanup.
    private func manageMenu(_ room: Room) -> some View {
        Menu {
            if room.state == .settling {
                Button {
                    showRollbackConfirm = true
                } label: {
                    Label("Reopen Claiming", systemImage: "arrow.uturn.backward.circle")
                }
            }
            if room.state != .closed {
                let kickable = room.members.filter { !$0.isHost }
                if !kickable.isEmpty {
                    Menu("Remove Member…") {
                        ForEach(kickable) { member in
                            Button("\(member.avatarEmoji) \(member.displayName)") {
                                memberToKick = member
                            }
                        }
                    }
                }
            }
            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Label("Delete Room", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.black)
                .frame(width: 44, height: 44)
                .background(Color.white)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
        }
    }

    /// Names the consequence when debts are still open. The actual teardown
    /// (CKShare / zone / member access) ships with milestone 4 — see
    /// `deleteRoom()`.
    private func deleteWarning(_ room: Room) -> String {
        let unsettled = room.members.contains { !$0.isHost && $0.paymentStatus != .hostConfirmed }
        if room.state != .closed, unsettled, !room.bills.isEmpty {
            return "Members still owe you — unsettled balances will be lost. This can't be undone."
        }
        return "This removes the room for everyone. This can't be undone."
    }

    private func deleteRoom() {
        // Milestone 4: tear down the CKShare / record zone and revoke every
        // member's access. Until that ships, deleting locally would strand
        // members on the share — so the entry point stops here, honestly.
        store.alert = StoreAlert(
            message: "Deleting a room arrives with cloud sync teardown (milestone 4). This room hasn't been changed."
        )
    }

    // MARK: - State-dependent pieces

    private func canEditBills(_ room: Room) -> Bool {
        room.state == .open || room.state == .claiming
    }

    /// First-time host path lives in content, where they look.
    private var emptyBillsCard: some View {
        VStack(spacing: 16) {
            Text("No bills yet")
                .font(.headline)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button {
                    showScanReceipt = true
                } label: {
                    Label("Scan Receipt", systemImage: "doc.viewfinder")
                }
                Button {
                    showAddBill = true
                } label: {
                    Label("Enter Manually", systemImage: "keyboard")
                }
            }
            .font(.subheadline.weight(.medium))
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    /// The existing working screens stay as sub-destinations: claiming
    /// oversight (incl. force-assign) and settlement (incl. payment
    /// confirmation) are not re-implemented here.
    @ViewBuilder
    private func subDestination(_ room: Room) -> some View {
        switch room.state {
        case .open:
            EmptyView()
        case .claiming:
            destinationCard("Items & Claims", systemImage: "checklist") {
                ClaimingView(store: store, roomID: roomID)
            }
        case .settling:
            destinationCard("Settlement", systemImage: "creditcard") {
                SettlementView(store: store, roomID: roomID)
            }
        case .closed:
            destinationCard("Final Summary", systemImage: "doc.text.magnifyingglass") {
                SettlementView(store: store, roomID: roomID)
            }
        }
    }

    private func destinationCard(
        _ title: String,
        systemImage: String,
        @ViewBuilder destination: () -> some View
    ) -> some View {
        NavigationLink(destination: destination()) {
            HStack {
                Label(title, systemImage: systemImage)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(20)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// The host's one primary action per state — advance the state machine.
    /// Nothing pinned once the room is closed.
    @ViewBuilder
    private func pinnedAction(_ room: Room) -> some View {
        if room.state != .closed {
            VStack {
                Button {
                    showAdvanceConfirm = true
                } label: {
                    Text(room.state.advanceLabel)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(
                            Color(
                                red: 82/255,
                                green: 126/255,
                                blue: 255/255
                            )
                        )
                        .clipShape(
                            Capsule()
                        )
                        .opacity(advanceDisabled(room) ? 0.4 : 1)
                }
                .buttonStyle(.plain)
                .disabled(advanceDisabled(room))
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)
            .background(Color.white)
        }
    }

    private func advanceDisabled(_ room: Room) -> Bool {
        switch room.state {
        case .open:
            return room.bills.isEmpty || room.members.count <= 1
        case .claiming:
            return false
        case .settling:
            return !room.members
                .filter { !$0.isHost }
                .allSatisfy { $0.paymentStatus == .hostConfirmed }
        case .closed:
            return true
        }
    }
}

#Preview {
    let store = MockRoomStore(rooms: MockData.rooms())
    NavigationStack {
        DetailView(store: store, roomID: store.rooms[0].id)
    }
}
