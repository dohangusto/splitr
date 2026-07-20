import SwiftUI
import SplitBillCore

/// Settlement: per-member breakdown from `SettlementCalculator`, payment
/// tracking (member marks paid → host confirms), and host-only close.
/// Read-only when the room is closed.
struct SettlementView: View {
    let store: any RoomStoring
    let roomID: UUID

    @State private var showCloseConfirm = false
    /// Host view: which member's breakdown is expanded (detail behind a tap).
    @State private var expandedMemberID: UUID?

    private var room: Room? { store.room(withID: roomID) }
    private var actingID: UUID? { store.actingMemberID(in: roomID) }
    private var actingIsHost: Bool { actingID == room?.hostMemberID }

    var body: some View {
        if let room, let actingID {
            content(room, actingID: actingID)
        } else {
            ContentUnavailableView("Room not found", systemImage: "questionmark.circle")
        }
    }

    @ViewBuilder
    private func content(_ room: Room, actingID: UUID) -> some View {
        let readOnly = room.state == .closed
        switch settlementResult(room) {
        case .failure(let unclaimedCount):
            ContentUnavailableView {
                Label("Items still unclaimed", systemImage: "exclamationmark.triangle")
            } description: {
                if actingIsHost {
                    Text("\(unclaimedCount) item\(unclaimedCount == 1 ? "" : "s") have no owner. Reopen claiming so members can claim them, or assign them yourself.")
                } else {
                    Text("\(unclaimedCount) item\(unclaimedCount == 1 ? "" : "s") have no owner yet. The host is sorting it out.")
                }
            }
            .toolbar {
                if actingIsHost, room.state == .settling {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Reopen Claiming", systemImage: "arrow.uturn.backward.circle") {
                            store.rollbackToClaiming(roomID: roomID)
                        }
                    }
                }
            }
        case .success(let settlement):
            List {
                if actingIsHost {
                    hostSection(settlement, room: room, readOnly: readOnly)
                    totalsSection(settlement, room: room)
                } else if let me = room.member(withID: actingID),
                          let share = settlement.settlement(for: actingID) {
                    mySection(member: me, share: share, readOnly: readOnly)
                }
            }
            .navigationTitle(readOnly ? "Final Summary" : "Settlement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar)
            .toolbar { settlementToolbar(room, actingID: actingID, readOnly: readOnly) }
            .confirmationDialog(
                "Close this room?",
                isPresented: $showCloseConfirm,
                titleVisibility: .visible
            ) {
                Button("Close Room", role: .destructive) {
                    store.advance(roomID: roomID)
                }
            } message: {
                Text("Closing is final. The room becomes read-only history.")
            }
        }
    }

    private enum SettlementResult {
        case success(Settlement)
        case failure(unclaimedCount: Int)
    }

    private func settlementResult(_ room: Room) -> SettlementResult {
        do {
            return .success(try SettlementCalculator.settle(room: room))
        } catch {
            let unclaimed = room.bills
                .flatMap(\.items)
                .filter { $0.claimState == .unclaimed }
                .count
            return .failure(unclaimedCount: max(unclaimed, 1))
        }
    }

    // MARK: - Toolbar

    /// The host's final "Close Room" is screen-scoped, so it lives here.
    /// The member's "I've Paid" is their primary action and lives in content.
    @ToolbarContentBuilder
    private func settlementToolbar(_ room: Room, actingID: UUID, readOnly: Bool) -> some ToolbarContent {
        if !readOnly, actingIsHost {
            ToolbarItem(placement: .confirmationAction) {
                Button("Close Room") {
                    showCloseConfirm = true
                }
                .disabled(!allConfirmed(room))
            }
        }
    }

    private func allConfirmed(_ room: Room) -> Bool {
        room.members
            .filter { !$0.isHost }
            .allSatisfy { $0.paymentStatus == .hostConfirmed }
    }

    // MARK: - Sections

    /// Host view: one row per owing member — name, amount, confirm — with
    /// the Items/Tax/Service breakdown behind a tap on the row.
    private func hostSection(_ settlement: Settlement, room: Room, readOnly: Bool) -> some View {
        Section {
            ForEach(room.members.filter { !$0.isHost }) { member in
                if let share = settlement.settlement(for: member.id) {
                    memberRow(member: member, share: share, readOnly: readOnly)
                    if expandedMemberID == member.id {
                        breakdownRows(share)
                    }
                }
            }
        } header: {
            Text("Who owes what")
        }
    }

    @ViewBuilder
    private func memberRow(member: Member, share: MemberSettlement, readOnly: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(member.avatarEmoji) \(member.displayName)")
                Spacer()
                Text(share.totalOwed.rupiah).bold()
            }
            HStack {
                statusLabel(member.paymentStatus)
                Spacer()
                if !readOnly, member.paymentStatus != .hostConfirmed {
                    Button("Confirm received") {
                        store.confirmPayment(of: member.id, roomID: roomID)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            expandedMemberID = expandedMemberID == member.id ? nil : member.id
        }
    }

    @ViewBuilder
    private func breakdownRows(_ share: MemberSettlement) -> some View {
        LabeledContent("Items") { Text(share.subtotal.rupiah) }
        LabeledContent("Tax (PB1)") { Text(share.taxShare.rupiah) }
        LabeledContent("Service") { Text(share.serviceShare.rupiah) }
    }

    @ViewBuilder
    private func statusLabel(_ status: PaymentStatus) -> some View {
        switch status {
        case .none:
            Label("Unpaid", systemImage: "circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .memberMarkedPaid:
            Label("Marked paid", systemImage: "checkmark.circle")
                .font(.caption)
                .foregroundStyle(.orange)
        case .hostConfirmed:
            Label("Settled", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        }
    }

    /// Member view: their own breakdown, total, and "I've Paid" — nothing
    /// about anyone else.
    private func mySection(member: Member, share: MemberSettlement, readOnly: Bool) -> some View {
        Section {
            breakdownRows(share)
            LabeledContent {
                Text(share.totalOwed.rupiah).bold()
            } label: {
                Text("You owe the host").bold()
            }
            if !readOnly {
                switch member.paymentStatus {
                case .none:
                    Button {
                        store.markPaid(roomID: roomID)
                    } label: {
                        Text("I've Paid")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                case .memberMarkedPaid:
                    statusLabel(.memberMarkedPaid)
                case .hostConfirmed:
                    statusLabel(.hostConfirmed)
                }
            } else {
                statusLabel(member.paymentStatus)
            }
        } header: {
            Text("Your share")
        }
    }

    /// Host only: the whole-bill arithmetic.
    private func totalsSection(_ settlement: Settlement, room: Room) -> some View {
        Section {
            LabeledContent("Subtotal") { Text(settlement.billSubtotal.rupiah) }
            LabeledContent("Tax (PB1)") { Text(settlement.taxTotal.rupiah) }
            LabeledContent("Service") { Text(settlement.serviceTotal.rupiah) }
            LabeledContent {
                Text(settlement.grandTotal.rupiah).bold()
            } label: {
                Text("Grand total").bold()
            }
        } header: {
            Text("Bill total")
        }
    }
}
