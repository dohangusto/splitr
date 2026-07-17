import SwiftUI
import SplitBillCore

/// Room hub: adapts to the room's state. Members, bills, host state controls,
/// and entry points into claiming / settlement.
struct RoomDetailView: View {
    let store: any RoomStoring
    let roomID: UUID

    @State private var showAddBill = false
    @State private var showScanReceipt = false
    @State private var showJoinMember = false
    @State private var showAdvanceConfirm = false
    @State private var showRollbackConfirm = false
    @State private var memberToKick: Member?
    @State private var billToEdit: Bill?
    @State private var billToDelete: Bill?
    @State private var inviteURL: URL?
    @State private var showNearbyHost = false

    private var room: Room? { store.room(withID: roomID) }
    private var actingID: UUID? { store.actingMemberID(in: roomID) }
    private var actingIsHost: Bool { actingID == room?.hostMemberID }

    var body: some View {
        if let room {
            content(room)
        } else {
            ContentUnavailableView("Room not found", systemImage: "questionmark.circle")
        }
    }

    private func content(_ room: Room) -> some View {
        List {
            navigationSection(room)
            membersSection(room)
            billsSection(room)
        }
        .listStyle(.insetGrouped)
        .navigationTitle(room.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar) // Hide the Home view's tab bar when pushed
        .toolbar { detailToolbar(room) }
        // The role's single next action, pinned in the content layer
        // (same `safeAreaBar` pattern as ClaimingView's running total —
        // no dependency on the tab bar or its accessory).
        .safeAreaBar(edge: .bottom) {
            pinnedAction(room)
        }
        .sheet(isPresented: $showAddBill) {
            AddBillView(store: store, roomID: roomID)
        }
        .sheet(isPresented: $showScanReceipt) {
            ReceiptScanFlow(store: store, roomID: roomID)
        }
        .sheet(item: $billToEdit) { bill in
            NavigationStack {
                AddBillForm(store: store, roomID: roomID, existingBill: bill)
            }
        }
        .alert(item: $billToDelete) { bill in
            Alert(
                title: Text("Delete \(bill.merchantName)?"),
                message: Text("All \(bill.items.count) items on this bill will be removed."),
                primaryButton: .destructive(Text("Delete")) {
                    ReceiptPhotoStore.delete(bill.photoReference)
                    store.removeBill(billID: bill.id, roomID: roomID)
                },
                secondaryButton: .cancel()
            )
        }
        .sheet(item: $inviteURL) { url in
            // Members who open this link join the room's shared CloudKit zone.
            ShareLinkSheet(url: url, roomName: room.name)
        }
        .sheet(isPresented: $showNearbyHost) {
            if let cloudStore = AppComposition.cloudStore {
                NearbyHostView(
                    store: cloudStore,
                    roomID: roomID,
                    roomName: room.name,
                    hostDisplayName: room.member(withID: room.hostMemberID)?.displayName ?? "Host",
                    onUseLink: { fetchInviteURL() }
                )
            }
        }
        .sheet(isPresented: $showJoinMember) {
            JoinMemberView(store: store, roomID: roomID)
        }
        .confirmationDialog(
            advanceQuestion(room.state),
            isPresented: $showAdvanceConfirm,
            titleVisibility: .visible
        ) {
            Button(advanceLabel(room.state), role: room.state == .settling ? .destructive : nil) {
                store.advance(roomID: roomID)
            }
        } message: {
            Text(advanceDetail(room.state))
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
    }

    /// Toolbar is simplified: gathers manual additions/invitation settings
    /// into a single menu button, keeping the rest of the interface focused on content.
    @ToolbarContentBuilder
    private func detailToolbar(_ room: Room) -> some ToolbarContent {
        if room.state == .settling, actingIsHost {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(role: .destructive) {
                        showRollbackConfirm = true
                    } label: {
                        Label("Reopen Claiming", systemImage: "arrow.uturn.backward.circle")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        // Host-only tools. Members get no toolbar: adding bills and people
        // is the host's job (the host assigns member IDs and sends the
        // CKShare invitation), so members must never see those controls.
        if actingIsHost, room.state == .open || room.state == .claiming {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showScanReceipt = true
                    } label: {
                        Label("Scan Receipt", systemImage: "doc.viewfinder")
                    }
                    Button {
                        showAddBill = true
                    } label: {
                        Label("Add Bill Manually", systemImage: "keyboard")
                    }
                } label: {
                    Image(systemName: "doc.badge.plus")
                }

                if AppComposition.cloudStore != nil {
                    Menu {
                        Button {
                            showNearbyHost = true
                        } label: {
                            Label("Add People Nearby", systemImage: "iphone.radiowaves.left.and.right")
                        }
                        Button {
                            fetchInviteURL()
                        } label: {
                            Label("Invite via Link", systemImage: "link.badge.plus")
                        }
                        Button {
                            showJoinMember = true
                        } label: {
                            Label("Add Member Manually", systemImage: "keyboard")
                        }
                    } label: {
                        Image(systemName: "person.badge.plus")
                    }
                } else {
                    // One entry isn't a menu: without CloudKit only manual
                    // add exists, so it's a direct button.
                    Button {
                        showJoinMember = true
                    } label: {
                        Image(systemName: "person.badge.plus")
                    }
                }
            }
        }
    }

    private func fetchInviteURL() {
        Task {
            inviteURL = await AppComposition.cloudStore?.inviteURL(roomID: roomID)
        }
    }

    /// Plain row links into the room's working screens — the door, not a
    /// dashboard. The members and bills sections below already answer
    /// "who's here" and "what's on the bill".
    @ViewBuilder
    private func navigationSection(_ room: Room) -> some View {
        switch room.state {
        case .open:
            EmptyView()
        case .claiming:
            Section {
                NavigationLink(destination: ClaimingView(store: store, roomID: room.id)) {
                    Text("Items")
                }
            }
        case .settling:
            Section {
                NavigationLink(destination: SettlementView(store: store, roomID: room.id)) {
                    Text("Settlement")
                }
            }
        case .closed:
            Section {
                NavigationLink(destination: SettlementView(store: store, roomID: room.id)) {
                    Text("Final Summary")
                }
            }
        }
    }

    /// Exactly one pinned primary action per role and state; nothing pinned
    /// when the role has no next action here.
    @ViewBuilder
    private func pinnedAction(_ room: Room) -> some View {
        if actingIsHost {
            switch room.state {
            case .open:
                pinnedButton("Start Claiming") { showAdvanceConfirm = true }
                    .disabled(room.bills.isEmpty || room.members.count <= 1)
            case .claiming:
                pinnedButton("Close Claiming") { showAdvanceConfirm = true }
            case .settling:
                pinnedButton("Close Room") { showAdvanceConfirm = true }
                    .disabled(!allConfirmed(room))
            case .closed:
                EmptyView()
            }
        } else if room.state == .settling,
                  let actingID,
                  let me = room.member(withID: actingID),
                  me.paymentStatus == PaymentStatus.none,
                  (try? SettlementCalculator.settle(room: room))?
                      .settlement(for: actingID)?.totalOwed ?? 0 > 0 {
            pinnedButton("I've Paid") { store.markPaid(roomID: roomID) }
        }
    }

    private func pinnedButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .padding(.horizontal)
    }

    private func allConfirmed(_ room: Room) -> Bool {
        room.members
            .filter { !$0.isHost }
            .allSatisfy { $0.paymentStatus == .hostConfirmed }
    }

    private func advanceLabel(_ state: RoomState) -> String {
        switch state {
        case .open: return "Start Claiming"
        case .claiming: return "Close Claiming & Settle"
        case .settling: return "Close Room"
        case .closed: return ""
        }
    }

    private func advanceQuestion(_ state: RoomState) -> String {
        switch state {
        case .open: return "Start claiming?"
        case .claiming: return "Close claiming?"
        case .settling: return "Close this room?"
        case .closed: return ""
        }
    }

    private func advanceDetail(_ state: RoomState) -> String {
        switch state {
        case .open:
            return "Members will start claiming their items. You can still add bills and members while claiming."
        case .claiming:
            return "Tax and service will be split proportionally and everyone sees what they owe. You can reopen claiming later if something's wrong."
        case .settling:
            return "Closing is final. The room becomes read-only history."
        case .closed:
            return ""
        }
    }

    // MARK: - Members

    private func membersSection(_ room: Room) -> some View {
        Section {
            if room.members.isEmpty {
                Text("No members yet").foregroundStyle(.secondary)
            }
            ForEach(room.members) { member in
                MemberRow(member: member, roomState: room.state)
                    .swipeActions(edge: .trailing) {
                        if actingIsHost, !member.isHost, room.state != .closed {
                            Button("Remove", role: .destructive) {
                                memberToKick = member
                            }
                        }
                    }
            }
        } header: {
            Text("Members")
        }
    }

    // MARK: - Bills

    private func billsSection(_ room: Room) -> some View {
        // Bills stay editable while the room is .open; claiming freezes them.
        let billsEditable = actingIsHost && (room.state == .open || room.state == .claiming)
        return Section {
            if room.bills.isEmpty {
                if actingIsHost, room.state == .open {
                    // First-time host path lives in content, where they look.
                    Button(action: { showScanReceipt = true }) {
                        Label("Scan Receipt", systemImage: "doc.viewfinder")
                    }
                    Button(action: { showAddBill = true }) {
                        Label("Enter Manually", systemImage: "keyboard")
                    }
                } else {
                    Text("No bills yet").foregroundStyle(.secondary)
                }
            }
            ForEach(room.bills) { bill in
                Button {
                    billToEdit = bill
                } label: {
                    BillRow(bill: bill, showsChevron: true)
                }
                .foregroundStyle(.primary)
                .swipeActions(edge: .trailing) {
                    if billsEditable {
                        Button("Delete", role: .destructive) {
                            billToDelete = bill
                        }
                    }
                }
            }
        } header: {
            Text("Bills")
        }
    }

}

// MARK: - Redesigned BillRow View

struct BillRow: View {
    let bill: Bill
    let showsChevron: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(bill.merchantName)
                    .font(.body)
                    .foregroundColor(.primary)
                Text("\(bill.items.count) items")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Text(bill.subtotal.rupiah)
                .font(.body)
                .foregroundColor(.secondary)

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Redesigned MemberRow View

struct MemberRow: View {
    let member: Member
    let roomState: RoomState

    var body: some View {
        HStack(spacing: 12) {
            Text(member.avatarEmoji)
                .font(.title2)
                .frame(width: 36, height: 36)
                .background(Color(.systemGray6), in: Circle())

            Text(member.displayName)
                .font(.body)
                .foregroundColor(.primary)
            if member.isHost {
                Text("Host")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if (roomState == .settling || roomState == .closed) && !member.isHost {
                PaymentStatusLabel(status: member.paymentStatus)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Redesigned PaymentStatusLabel View

struct PaymentStatusLabel: View {
    let status: PaymentStatus

    var body: some View {
        switch status {
        case .none:
            Text("Unpaid")
                .font(.subheadline)
                .foregroundColor(.secondary)
        case .memberMarkedPaid:
            Text("Pending")
                .font(.subheadline)
                .foregroundColor(.orange)
        case .hostConfirmed:
            Text("Settled")
                .font(.subheadline)
                .foregroundColor(.green)
        }
    }
}

