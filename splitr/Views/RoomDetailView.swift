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
            #if DEBUG
            debugActingSection(room)
            #endif

            // Horizontal Stepper Section
            Section {
                RoomProgressStepper(currentState: room.state)
                    .padding(.vertical, 8)
            }

            // Contextual Guidance CTA Card Section
            if let actingID {
                guidanceSection(room: room, actingID: actingID)
            }

            membersSection(room)
            billsSection(room)
        }
        .listStyle(.insetGrouped)
        .navigationTitle(room.name)
        .navigationBarTitleDisplayMode(.inline)
        // Detail screen owns its chrome: Home's tab bar steps aside so the
        // room's own bottom-bar actions are the only floating layer.
        .toolbar(.hidden, for: .tabBar)
        .toolbar { detailToolbar(room) }
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
        if room.state == .open || room.state == .claiming {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if actingIsHost {
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
                        
                        Divider()
                        
                        if AppComposition.cloudStore != nil {
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
                        }
                    }
                    Button {
                        showJoinMember = true
                    } label: {
                        Label("Add Member Manually", systemImage: "keyboard")
                    }
                } label: {
                    Label("Add Items or People", systemImage: "plus.circle")
                }
            }
        }
    }

    private func fetchInviteURL() {
        Task {
            inviteURL = await AppComposition.cloudStore?.inviteURL(roomID: roomID)
        }
    }

    // MARK: - Debug perspective switcher

    #if DEBUG
    private func debugActingSection(_ room: Room) -> some View {
        Section {
            Picker(selection: Binding(
                get: { actingID ?? room.hostMemberID },
                set: { store.setActingMember($0, in: roomID) }
            )) {
                ForEach(room.members) { member in
                    Text("\(member.avatarEmoji) \(member.displayName)\(member.isHost ? " (host)" : "")")
                        .tag(member.id)
                }
            } label: {
                Label("Acting as", systemImage: "wrench.and.screwdriver")
            }
        } header: {
            Text("Debug")
        } footer: {
            Text("Simulator-only stand-in for separate devices. Every action below runs as this member.")
        }
    }
    #endif

    @ViewBuilder
    private func guidanceSection(room: Room, actingID: UUID) -> some View {
        let actingIsHost = actingID == room.hostMemberID
        
        switch room.state {
        case .open:
            if actingIsHost {
                Section {
                    if room.bills.isEmpty {
                        Button(action: { showScanReceipt = true }) {
                            Label("Scan Receipt", systemImage: "doc.viewfinder")
                        }
                        Button(action: { showAddBill = true }) {
                            Label("Enter Manually", systemImage: "keyboard")
                        }
                    } else if room.members.count <= 1 {
                        Button(action: { showNearbyHost = true }) {
                            Label("Add People Nearby", systemImage: "iphone.radiowaves.left.and.right")
                        }
                        Button(action: { fetchInviteURL() }) {
                            Label("Share Invite Link", systemImage: "link.badge.plus")
                        }
                    } else {
                        Button(action: { showAdvanceConfirm = true }) {
                            Text("Start Claiming Phase")
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                } header: {
                    Text("Host Setup Checklist")
                } footer: {
                    if room.bills.isEmpty {
                        Text("Start by scanning restaurant receipts.")
                    } else if room.members.count <= 1 {
                        Text("Invite friends to join the room.")
                    } else {
                        Text("You have bills and members. Ready to start claiming.")
                    }
                }
            } else {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("Waiting for Host...")
                                .font(.headline)
                            Text("The host is setting up bills and members.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.vertical, 16)
                        Spacer()
                    }
                }
            }
            
        case .claiming:
            let totalItems = room.bills.flatMap(\.items).count
            let claimedItems = room.bills.flatMap(\.items).filter {
                if case .unclaimed = $0.claimState { return false }
                return true
            }.count
            let subtotal = claimedSubtotal(room: room, memberID: actingID)
            
            Section {
                HStack {
                    Text("Items Claimed")
                    Spacer()
                    Text("\(claimedItems) of \(totalItems)")
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("Your Subtotal")
                    Spacer()
                    Text(subtotal.rupiah)
                        .foregroundColor(.secondary)
                }
                
                NavigationLink(destination: ClaimingView(store: store, roomID: room.id)) {
                    Text("Claim Items")
                }
                
                if actingIsHost {
                    Button(action: { showAdvanceConfirm = true }) {
                        Text("Close Claiming & Settle")
                    }
                }
            } header: {
                Text("Pick Your Items")
            } footer: {
                Text("Select the food and drinks you ordered.")
            }
            
        case .settling:
            if actingIsHost {
                let totalMembers = room.members.filter { !$0.isHost }.count
                let confirmedMembers = room.members.filter { !$0.isHost && $0.paymentStatus == .hostConfirmed }.count
                let allSettled = confirmedMembers == totalMembers && totalMembers > 0
                
                Section {
                    HStack {
                        Text("Settlement Progress")
                        Spacer()
                        Text("\(confirmedMembers) of \(totalMembers) paid")
                            .foregroundColor(.secondary)
                    }
                    
                    NavigationLink(destination: SettlementView(store: store, roomID: room.id)) {
                        Text("View Payment Details")
                    }
                    
                    Button(action: { showAdvanceConfirm = true }) {
                        Text("Close Room & Finish")
                            .frame(maxWidth: .infinity, alignment: .center)
                            .foregroundColor(allSettled ? .blue : .secondary)
                    }
                    .disabled(!allSettled)
                    
                    Button(action: { showRollbackConfirm = true }) {
                        Text("Reopen Claiming")
                    }
                    .foregroundColor(.red)
                    
                } header: {
                    Text("Host Settlement Dashboard")
                } footer: {
                    Text("Confirm payments from members. Once everyone has paid, close the room.")
                }
            } else {
                let settlement = try? SettlementCalculator.settle(room: room)
                let memberShare = settlement?.settlement(for: actingID)
                let totalOwed = memberShare?.totalOwed ?? 0
                let me = room.member(withID: actingID)
                
                Section {
                    if totalOwed == 0 {
                        Text("You don't owe any money.")
                            .foregroundColor(.secondary)
                    } else {
                        HStack {
                            Text("Total Owed")
                            Spacer()
                            Text(totalOwed.rupiah)
                                .foregroundColor(.primary)
                        }
                        
                        if let me {
                            if me.paymentStatus == .none {
                                Button(action: { store.markPaid(roomID: room.id) }) {
                                    Text("I've Paid the Host")
                                        .frame(maxWidth: .infinity, alignment: .center)
                                }
                            } else if me.paymentStatus == .memberMarkedPaid {
                                HStack {
                                    ProgressView()
                                        .padding(.trailing, 8)
                                    Text("Waiting for confirmation")
                                        .foregroundColor(.secondary)
                                }
                            } else {
                                HStack {
                                    Image(systemName: "checkmark.seal.fill")
                                        .foregroundColor(.green)
                                    Text("Payment Confirmed")
                                        .foregroundColor(.primary)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Your Settlement")
                } footer: {
                    if totalOwed > 0 {
                        Text("Please transfer your share to the host.")
                    }
                }
            }
            
        case .closed:
            let settlement = try? SettlementCalculator.settle(room: room)
            Section {
                if let grandTotal = settlement?.grandTotal {
                    HStack {
                        Text("Grand Total")
                        Spacer()
                        Text(grandTotal.rupiah)
                            .foregroundColor(.secondary)
                    }
                }
                
                NavigationLink(destination: SettlementView(store: store, roomID: room.id)) {
                    Text("View Final Summary")
                }
            } header: {
                Text("Room Settled & Closed")
            } footer: {
                Text("This split bill session is completed and archived.")
            }
        }
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
        } footer: {
            if actingIsHost, room.members.count > 1, room.state != .closed {
                Text("Swipe a member to remove them. Their claimed items return to unclaimed.")
            }
        }
    }

    // MARK: - Bills

    private func billsSection(_ room: Room) -> some View {
        // Bills stay editable while the room is .open; claiming freezes them.
        let billsEditable = actingIsHost && room.state == .open
        return Section {
            if room.bills.isEmpty {
                Text("No bills yet. Scan the receipt using options above to get started.")
                    .foregroundStyle(.secondary)
            }
            ForEach(room.bills) { bill in
                if billsEditable {
                    Button {
                        billToEdit = bill
                    } label: {
                        BillRow(bill: bill, showsChevron: true)
                    }
                    .foregroundStyle(.primary)
                    .swipeActions(edge: .trailing) {
                        Button("Delete", role: .destructive) {
                            billToDelete = bill
                        }
                    }
                } else {
                    BillRow(bill: bill, showsChevron: false)
                }
            }
        } header: {
            Text("Bills")
        } footer: {
            if billsEditable, !room.bills.isEmpty {
                Text("Tap a bill to fix scan mistakes, or swipe to delete it. Bills lock once claiming starts.")
            }
        }
    }

    private func claimedSubtotal(room: Room, memberID: UUID) -> Int {
        let prices = Dictionary(
            room.bills.flatMap(\.items).map { ($0.id, $0.unitPrice) },
            uniquingKeysWith: { first, _ in first }
        )
        return room.claims(for: memberID)
            .reduce(Fraction.zero) { $0 + $1.portion * (prices[$1.itemID] ?? 0) }
            .flooredValue
    }
}

// MARK: - Stepper View

private struct RoomProgressStepper: View {
    let currentState: RoomState

    var body: some View {
        HStack(spacing: 0) {
            ForEach(RoomState.allCases, id: \.self) { state in
                let order = state.order
                let currentOrder = currentState.order
                let isCompleted = order < currentOrder
                let isActive = state == currentState

                VStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(isCompleted ? Color.green : (isActive ? state.color : Color(.systemGray5)))
                            .frame(width: 28, height: 28)

                        if isCompleted {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white)
                        } else {
                            Image(systemName: state.icon)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(isActive ? .white : .secondary)
                        }
                    }

                    Text(state.title)
                        .font(.system(size: 10, weight: isActive ? .semibold : .regular))
                        .foregroundStyle(isActive ? .primary : .secondary)
                }
                .frame(maxWidth: .infinity)

                if state != .closed {
                    let nextIsCompletedOrActive = (order + 1) <= currentOrder
                    Rectangle()
                        .fill(nextIsCompletedOrActive ? Color.green : Color(.systemGray4))
                        .frame(height: 2)
                        .frame(maxWidth: .infinity)
                        .offset(y: -9)
                }
            }
        }
    }
}

// MARK: - RoomState Extensions

private extension RoomState {
    var order: Int {
        switch self {
        case .open: return 0
        case .claiming: return 1
        case .settling: return 2
        case .closed: return 3
        }
    }

    var icon: String {
        switch self {
        case .open: return "plus.bubble.fill"
        case .claiming: return "hand.tap.fill"
        case .settling: return "banknote.fill"
        case .closed: return "checkmark.seal.fill"
        }
    }

    var title: String {
        switch self {
        case .open: return "Setup"
        case .claiming: return "Claiming"
        case .settling: return "Settling"
        case .closed: return "Closed"
        }
    }

    var color: Color {
        switch self {
        case .open: return .blue
        case .claiming: return .orange
        case .settling: return .purple
        case .closed: return .green
        }
    }
}

// MARK: - Redesigned BillRow View

struct BillRow: View {
    let bill: Bill
    let showsChevron: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.blue)
                    .frame(width: 30, height: 30)
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.white)
            }

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

            VStack(alignment: .leading, spacing: 2) {
                Text(member.displayName)
                    .font(.body)
                    .foregroundColor(.primary)
                Text(member.isHost ? "Room Owner" : "Member")
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
