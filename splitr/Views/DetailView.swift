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
    @State private var showAddBillOptions = false
    /// Chosen from the add-bill options sheet, applied on its dismissal so
    /// the follow-on flow presents cleanly after the sheet closes.
    @State private var pendingBillEntry: BillEntry?
    @State private var billEntry: BillEntry?
    @State private var billToEdit: Bill?
    @State private var previewPhoto: PreviewPhoto?
    @State private var showAdvanceConfirm = false
    @State private var showRollbackConfirm = false
    @State private var showDeleteConfirm = false
    /// Local buffer for the editable room name (committed on submit/focus loss).
    @State private var draftName = ""

    private var room: Room? { store.room(withID: roomID) }

    /// Persists a renamed room, ignoring empty or unchanged input.
    private func commitRename(_ room: Room) {
        let trimmed = draftName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            draftName = room.name // restore; empty names aren't allowed
            return
        }
        guard trimmed != room.name else { return }
        store.renameRoom(roomID: roomID, to: trimmed)
    }

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
            Color("PrimaryBackground")
            .ignoresSafeArea()

            // MARK: Content
            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {

                    // Header, with the host's Manage powers tucked trailing.
                    ZStack(alignment: .trailing) {
                        NavigationHeader(title: "Detail")
                        manageMenu(room)
                    }

                    // Split Bill Name — the host can rename the room in place;
                    // committed on return / focus loss, never per keystroke.
                    SplitBillNameCard(
                        billName: $draftName,
                        isEditable: room.state != .closed,
                        onCommit: { commitRename(room) }
                    )
                    .onAppear { if draftName.isEmpty { draftName = room.name } }
                    .onChange(of: room.name) { _, newValue in
                        // Keep the field in sync with remote changes when the
                        // host isn't mid-edit (they own renames, so this is rare).
                        if draftName != newValue { draftName = newValue }
                    }

                    // People
                    PeopleCard(people: room.members.map(\.avatarEmoji)) {
                        showingPeopleList = true
                    }

                    // Bills Photo — the "+" is the host's add-a-bill entry
                    // point, and it exists only while the room is `.open`:
                    // once claiming starts the bill set is fixed. Thumbnails
                    // stay tappable to preview in any state. Hidden entirely
                    // when there's nothing to show and nothing to add.
                    let photos = room.bills.compactMap { ReceiptPhotoStore.load($0.photoReference) }
                    let canAddBill = room.state == .open
                    if !photos.isEmpty || canAddBill {
                        BillsPhotoCard(
                            photos: photos,
                            showsAddButton: canAddBill,
                            onAddTapped: { showAddBillOptions = true },
                            onPhotoTapped: { previewPhoto = PreviewPhoto(image: $0) }
                        )
                    }

                    // Bill Detail — one card per bill, straight from Core.
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
        .sheet(item: $previewPhoto) { preview in
            ReceiptPhotoPreview(image: preview.image)
        }
        // Three weighty, icon-bearing choices deserve a real detented sheet,
        // not an action-sheet. The chosen entry is applied on dismissal so
        // the follow-on flow presents cleanly after this sheet closes.
        .sheet(isPresented: $showAddBillOptions, onDismiss: {
            if let pendingBillEntry {
                billEntry = pendingBillEntry
                self.pendingBillEntry = nil
            }
        }) {
            AddBillOptionsSheet { entry in
                pendingBillEntry = entry
                showAddBillOptions = false
            }
            .presentationDetents([.height(320)])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $billEntry) { entry in
            switch entry {
            case .camera:
                ReceiptScanFlow(store: store, roomID: roomID, source: .camera)
            case .photo:
                ReceiptScanFlow(store: store, roomID: roomID, source: .photoLibrary)
            case .manual:
                AddBillView(store: store, roomID: roomID)
            }
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
            // Removing a member now lives on each person's row inside the
            // People list sheet, next to who it acts on — not up here.
            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Label("Delete Room", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(.callout, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .background(Color(.secondarySystemGroupedBackground))
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
                // The host claims their own items through the same surface a
                // member uses — MemberClaim is role-aware (host force-assign
                // stays available inside it), so there's one claiming view.
                MemberClaim(store: store, roomID: roomID)
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
            .background(Color(.secondarySystemGroupedBackground))
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
                // Settling can't complete while items have no owner. Rather
                // than a dead, disabled "Close Room" button, say what's wrong
                // and offer the one action that fixes it — reopen claiming.
                if room.state == .settling, unclaimedCount(room) > 0 {
                    reopenClaimingPrompt(room)
                } else {
                    Button {
                        showAdvanceConfirm = true
                    } label: {
                        Text(room.state.advanceLabel)
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 56)
                            .background(
                                Color("SplitAirBlue")
                            )
                            .clipShape(
                                Capsule()
                            )
                            .opacity(advanceDisabled(room) ? 0.4 : 1)
                    }
                    .buttonStyle(.plain)
                    .disabled(advanceDisabled(room))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)
            .background(Color(.secondarySystemGroupedBackground))
        }
    }

    /// Number of items in the room with no owner — what blocks settlement.
    private func unclaimedCount(_ room: Room) -> Int {
        room.bills.flatMap(\.items).filter { $0.claimState == .unclaimed }.count
    }

    /// Shown in `.settling` when items are still unclaimed: names the problem
    /// and makes reopening claiming the explicit, intentional next step.
    @ViewBuilder
    private func reopenClaimingPrompt(_ room: Room) -> some View {
        let count = unclaimedCount(room)
        VStack(spacing: 12) {
            Label(
                "\(count) item\(count == 1 ? "" : "s") still have no owner",
                systemImage: "exclamationmark.triangle.fill"
            )
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.orange)
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("Settlement can't be finalized until every item is claimed or assigned. Reopen claiming to sort them out.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                showRollbackConfirm = true
            } label: {
                Text("Reopen Claiming")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 56)
                    .background(Color.orange)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
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

/// The three ways a host starts a new bill. Identifiable so `.sheet(item:)`
/// can drive the follow-on flow.
private enum BillEntry: Identifiable {
    case camera
    case photo
    case manual
    var id: Self { self }
}

/// The add-a-bill chooser: a detented bottom sheet of three icon-bearing
/// options. Camera and Photo both feed the same OCR pipeline; Manual opens
/// a blank bill form. All three still pass through the edit screen before a
/// `Bill` is ever created.
private struct AddBillOptionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onSelect: (BillEntry) -> Void

    var body: some View {
        NavigationStack {
            List {
                row(.camera, title: "Open Camera",
                    subtitle: "Scan the receipt with the camera",
                    systemImage: "camera.fill")
                row(.photo, title: "Select from Photo",
                    subtitle: "Pick a receipt photo from your library",
                    systemImage: "photo.on.rectangle")
                row(.manual, title: "Enter Manually",
                    subtitle: "Type the items in yourself",
                    systemImage: "keyboard")
            }
            .navigationTitle("Add a bill")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .tint(.primary)
                }
            }
        }
    }

    private func row(
        _ entry: BillEntry,
        title: String,
        subtitle: String,
        systemImage: String
    ) -> some View {
        Button {
            onSelect(entry)
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(.primary)
                    .frame(width: 40, height: 40)
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .padding(.vertical, 4)
        }
        // Plain style so the row keeps its own black/grey text instead of the
        // list's accent tint (which rendered the labels blue).
        .buttonStyle(.plain)
    }
}

/// Wraps a tapped receipt photo so `.sheet(item:)` can present it (UIImage
/// isn't Identifiable on its own).
private struct PreviewPhoto: Identifiable {
    let id = UUID()
    let image: UIImage
}

/// Full-screen preview of a receipt photo, pinch-to-zoom and double-tap so
/// small print stays readable (same gesture model as `ReceiptPhotoPane`).
private struct ReceiptPhotoPreview: View {
    let image: UIImage

    @Environment(\.dismiss) private var dismiss
    @State private var zoom: CGFloat = 1
    @State private var steadyZoom: CGFloat = 1

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ScrollView([.horizontal, .vertical], showsIndicators: false) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(
                            width: proxy.size.width * zoom,
                            height: proxy.size.height * zoom
                        )
                }
                .defaultScrollAnchor(.center)
            }
            .background(Color(.systemBackground))
            .gesture(
                MagnifyGesture()
                    .onChanged { zoom = min(max(steadyZoom * $0.magnification, 1), 6) }
                    .onEnded { _ in steadyZoom = zoom }
            )
            .onTapGesture(count: 2) {
                withAnimation(.snappy) {
                    zoom = zoom > 1.01 ? 1 : 2.5
                    steadyZoom = zoom
                }
            }
            .navigationTitle("Receipt photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    let store = MockRoomStore(rooms: MockData.rooms())
    NavigationStack {
        DetailView(store: store, roomID: store.rooms[0].id)
    }
}
