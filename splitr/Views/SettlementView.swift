import SwiftUI
import SplitBillCore

/// Settlement: per-member breakdown from `SettlementCalculator`, payment
/// tracking (member marks paid → host confirms), and host-only close.
/// Read-only when the room is closed.
struct SettlementView: View {
    let store: any RoomStoring
    let roomID: UUID

    @State private var showCloseConfirm = false

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
                Text("\(unclaimedCount) item\(unclaimedCount == 1 ? "" : "s") have no owner. Reopen claiming so members can claim them, or assign them yourself.")
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
                ForEach(room.members) { member in
                    if let share = settlement.settlement(for: member.id) {
                        memberSection(
                            member: member,
                            share: share,
                            room: room,
                            actingID: actingID,
                            readOnly: readOnly
                        )
                    }
                }
                totalsSection(settlement, room: room, readOnly: readOnly)
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

    /// Settlement's own actions, in the top toolbar: the acting member's
    /// "I've Paid" and the host's final "Close Room". Per-member confirms
    /// stay on the member rows they belong to.
    @ToolbarContentBuilder
    private func settlementToolbar(_ room: Room, actingID: UUID, readOnly: Bool) -> some ToolbarContent {
        if !readOnly {
            if let acting = room.member(withID: actingID),
               !acting.isHost, acting.paymentStatus == .none {
                ToolbarItem(placement: .confirmationAction) {
                    Button("I've Paid") {
                        store.markPaid(roomID: roomID)
                    }
                }
            }
            if actingIsHost {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close Room") {
                        showCloseConfirm = true
                    }
                    .disabled(!allConfirmed(room))
                }
            }
        }
    }

    private func allConfirmed(_ room: Room) -> Bool {
        room.members
            .filter { !$0.isHost }
            .allSatisfy { $0.paymentStatus == .hostConfirmed }
    }

    // MARK: - Sections

    private func memberSection(
        member: Member,
        share: MemberSettlement,
        room: Room,
        actingID: UUID,
        readOnly: Bool
    ) -> some View {
        Section {
            LabeledContent("Items") { Text(share.subtotal.rupiah) }
            LabeledContent("Tax (PB1)") { Text(share.taxShare.rupiah) }
            LabeledContent("Service") { Text(share.serviceShare.rupiah) }
            LabeledContent {
                Text(share.totalOwed.rupiah).bold()
            } label: {
                Text(member.isHost ? "Their share" : "Owes the host").bold()
            }

            if !member.isHost {
                paymentRow(member: member, room: room, actingID: actingID, readOnly: readOnly)
            }
        } header: {
            HStack {
                Text("\(member.avatarEmoji) \(member.displayName)")
                if member.isHost {
                    Text("· paid the bill")
                }
            }
        }
    }

    /// The acting member's own "I've Paid" lives in the bottom toolbar;
    /// the host's per-member confirm stays here because it is contextual
    /// to this row (one control per member).
    @ViewBuilder
    private func paymentRow(member: Member, room: Room, actingID: UUID, readOnly: Bool) -> some View {
        HStack(spacing: 12) {
            checkmark(
                done: member.paymentStatus != .none,
                label: "Paid"
            )
            checkmark(
                done: member.paymentStatus == .hostConfirmed,
                label: "Received"
            )
            Spacer()
            if !readOnly, actingIsHost, member.paymentStatus != .hostConfirmed {
                Button("Confirm received") { store.confirmPayment(of: member.id, roomID: roomID) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }

    private func checkmark(done: Bool, label: String) -> some View {
        Label(label, systemImage: done ? "checkmark.circle.fill" : "circle")
            .font(.caption)
            .foregroundStyle(done ? .green : .secondary)
    }

    private func totalsSection(_ settlement: Settlement, room: Room, readOnly: Bool) -> some View {
        Section {
            LabeledContent("Subtotal") { Text(settlement.billSubtotal.rupiah) }
            LabeledContent("Tax (PB1)") { Text(settlement.taxTotal.rupiah) }
            LabeledContent("Service") { Text(settlement.serviceTotal.rupiah) }
            LabeledContent {
                Text(settlement.grandTotal.rupiah).bold()
            } label: {
                Text("Grand total").bold()
            }
            if settlement.roundingRemainder > 0 {
                Text("Host absorbs \(settlement.roundingRemainder.rupiah) of rounding.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Bill total")
        } footer: {
            if !readOnly, actingIsHost, !allConfirmed(room) {
                Text("You can close the room once every member's payment is confirmed.")
            }
        }
    }
}
