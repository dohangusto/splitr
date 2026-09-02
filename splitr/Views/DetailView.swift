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
    @Environment(\.dismiss) private var dismiss

    @State private var showingPeopleList = false
    @State private var showScanReceipt = false
    @State private var showAddBill = false
    @State private var selectedPhotoBill: Bill?
    @State private var navigateToClaiming = false
    @State private var showDeleteConfirmation = false
    @State private var inviteURL: URL?

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

                    // Split Bill Name - editable and fully persisted to store
                    SplitBillNameCard(
                        billName: Binding(
                            get: { room.name },
                            set: { store.renameRoom(roomID: roomID, to: $0) }
                        )
                    )

                    // People
                    PeopleCard(people: room.members.map(\.avatarEmoji)) {
                        showingPeopleList = true
                    }

                    // Bills Photo
                    BillsPhotoCard(
                        bills: room.bills,
                        onAddTapped: { showScanReceipt = true },
                        onPhotoTapped: { bill, image in
                            selectedPhotoBill = bill
                        }
                    )

                    // Bill Detail — one card per bill, straight from Core.
                    if room.bills.isEmpty, room.state == .open {
                        emptyBillsCard
                    }
                    ForEach(room.bills) { bill in
                        BillDetailCard(
                            store: store,
                            roomID: roomID,
                            bill: bill,
                            canEdit: room.state == .open
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
        .sheet(item: $selectedPhotoBill) { bill in
            let imageRef = bill.photoReference ?? ""
            let image = ReceiptPhotoStore.load(imageRef) ?? UIImage(named: imageRef) ?? UIImage()
            FullScreenPhotoViewer(image: image, bill: bill) {
                store.removeBill(billID: bill.id, roomID: roomID)
            }
        }
        .navigationDestination(isPresented: $navigateToClaiming) {
            MemberClaim(store: store, roomID: roomID)
        }
        .sheet(item: $inviteURL) { url in
            ShareLinkSheet(url: url, roomName: room.name)
        }
        .confirmationDialog(
            "Are you sure you want to delete this room?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Room", role: .destructive) {
                deleteRoom()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(deleteWarning(room))
        }
        .onAppear {
            // no-op kept to preserve view structure
        }
    }

    // MARK: - Manage (host exception powers, off the main surface)

    /// Contents are state-dependent: rollback only in settling, kick while
    /// the room is live, delete always — a finished room still needs cleanup.
    private func manageMenu(_ room: Room) -> some View {
        Menu {
            if room.state != .closed {
                Button {
                    Task {
                        inviteURL = await store.inviteURL(roomID: roomID)
                    }
                } label: {
                    Label("Share Room Link", systemImage: "link")
                }
            }
            if room.state == .settling {
                Button {
                    store.rollbackToClaiming(roomID: roomID)
                } label: {
                    Label("Reopen Claiming", systemImage: "arrow.uturn.backward.circle")
                }
            }
            if room.state != .closed {
                let kickable = room.members.filter { !$0.isHost }
                if !kickable.isEmpty {
                    Menu("Remove Member…") {
                        ForEach(kickable) { member in
                            Button {
                                store.kick(memberID: member.id, roomID: roomID)
                            } label: {
                                Label {
                                    Text(member.displayName)
                                } icon: {
                                    if let uiImage = UIImage(named: member.avatarEmoji) {
                                        Image(uiImage: uiImage)
                                    } else {
                                        Text(member.avatarEmoji)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            Button(role: .destructive) {
                showDeleteConfirmation = true
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
        store.deleteRoom(roomID: roomID)
        dismiss()
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
                MemberClaim(store: store, roomID: roomID)
            }
        case .settling:
            destinationCard("Settlement", systemImage: "creditcard") {
                PaymentStatusView(store: store, roomID: roomID)
            }
        case .closed:
            destinationCard("Final Summary", systemImage: "doc.text.magnifyingglass") {
                PaymentStatusView(store: store, roomID: roomID)
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
                    if room.state == .open {
                        store.advance(roomID: roomID)
                        navigateToClaiming = true
                    } else {
                        store.advance(roomID: roomID)
                    }
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

// MARK: - Full Screen Photo Viewer

struct FullScreenPhotoViewer: View {
    let image: UIImage
    let bill: Bill
    let onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding()
            }
            .navigationTitle(bill.merchantName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(.white)
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        onDelete()
                        dismiss()
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                }
            }
        }
    }
}
