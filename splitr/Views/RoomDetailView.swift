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

            stateSection(room)
            membersSection(room)
            billsSection(room)
        }
        .navigationTitle(room.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAddBill) {
            AddBillView(store: store, roomID: roomID)
        }
        .sheet(isPresented: $showScanReceipt) {
            ReceiptScanFlow(store: store, roomID: roomID)
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
        .listRowBackground(Color.yellow.opacity(0.15))
    }
    #endif

    // MARK: - State

    private func stateSection(_ room: Room) -> some View {
        Section("Stage") {
            HStack {
                RoomStateBadge(state: room.state)
                Text(stateDescription(room))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if room.state == .claiming {
                NavigationLink {
                    ClaimingView(store: store, roomID: roomID)
                } label: {
                    Label("Claim Items", systemImage: "hand.tap")
                }
            }
            if room.state == .settling || room.state == .closed {
                NavigationLink {
                    SettlementView(store: store, roomID: roomID)
                } label: {
                    Label(room.state == .closed ? "Final Summary" : "Settlement", systemImage: "banknote")
                }
            }

            if actingIsHost, room.state != .closed, room.state != .settling {
                Button {
                    showAdvanceConfirm = true
                } label: {
                    Label(advanceLabel(room.state), systemImage: "arrow.forward.circle")
                }
            }
            if actingIsHost, room.state == .settling {
                Button {
                    showRollbackConfirm = true
                } label: {
                    Label("Reopen Claiming", systemImage: "arrow.uturn.backward.circle")
                }
            }
        }
    }

    private func stateDescription(_ room: Room) -> String {
        switch room.state {
        case .open: "Invite members and add bills."
        case .claiming: "Everyone picks their own items."
        case .settling: "Pay the host back. Close the room in Settlement once everyone is confirmed."
        case .closed: "Read-only history."
        }
    }

    private func advanceLabel(_ state: RoomState) -> String {
        switch state {
        case .open: "Start Claiming"
        case .claiming: "Close Claiming & Settle"
        case .settling: "Close Room"
        case .closed: ""
        }
    }

    private func advanceQuestion(_ state: RoomState) -> String {
        switch state {
        case .open: "Start claiming?"
        case .claiming: "Close claiming?"
        case .settling: "Close this room?"
        case .closed: ""
        }
    }

    private func advanceDetail(_ state: RoomState) -> String {
        switch state {
        case .open:
            "Members will start claiming their items. You can still add bills and members while claiming."
        case .claiming:
            "Tax and service will be split proportionally and everyone sees what they owe. You can reopen claiming later if something's wrong."
        case .settling:
            "Closing is final. The room becomes read-only history."
        case .closed:
            ""
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
            if room.state == .open || room.state == .claiming {
                Button {
                    showJoinMember = true
                } label: {
                    Label("Add Member", systemImage: "person.badge.plus")
                }
                if actingIsHost, AppComposition.cloudStore != nil {
                    Button {
                        showNearbyHost = true
                    } label: {
                        Label("Add People Nearby", systemImage: "iphone.radiowaves.left.and.right")
                    }
                    Button {
                        fetchInviteURL()
                    } label: {
                        Label("Invite via iCloud Link", systemImage: "link.badge.plus")
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
        Section("Bills") {
            if room.bills.isEmpty {
                Text("No bills yet. Add the receipt to get started.")
                    .foregroundStyle(.secondary)
            }
            ForEach(room.bills) { bill in
                VStack(alignment: .leading, spacing: 2) {
                    Text(bill.merchantName).font(.headline)
                    Text("\(bill.items.count) items · subtotal \(bill.subtotal.rupiah)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            if actingIsHost, room.state == .open || room.state == .claiming {
                Button {
                    showScanReceipt = true
                } label: {
                    Label("Scan Receipt", systemImage: "doc.viewfinder")
                }
                Button {
                    showAddBill = true
                } label: {
                    Label("Enter Bill Manually", systemImage: "doc.badge.plus")
                }
            }
        }
    }
}

struct MemberRow: View {
    let member: Member
    let roomState: RoomState

    var body: some View {
        HStack {
            Text(member.avatarEmoji).font(.title3)
            Text(member.displayName)
            if member.isHost {
                Text("HOST")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.tint.opacity(0.15), in: .capsule)
                    .foregroundStyle(.tint)
            }
            Spacer()
            if roomState == .settling || roomState == .closed, !member.isHost {
                PaymentStatusLabel(status: member.paymentStatus)
            }
        }
    }
}

struct PaymentStatusLabel: View {
    let status: PaymentStatus

    var body: some View {
        switch status {
        case .none:
            Text("unpaid")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .memberMarkedPaid:
            Label("paid", systemImage: "checkmark")
                .font(.caption)
                .foregroundStyle(.orange)
        case .hostConfirmed:
            Label("settled", systemImage: "checkmark.seal.fill")
                .font(.caption)
                .foregroundStyle(.green)
        }
    }
}
