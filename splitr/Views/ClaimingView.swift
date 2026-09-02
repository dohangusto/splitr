import SwiftUI
import SplitBillCore

/// Claiming: items grouped by bill, per-item actions for the acting member,
/// host force-assign, and a running "your items so far" footer.
struct ClaimingView: View {
    let store: any RoomStoring
    let roomID: UUID

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

    private func content(_ room: Room, actingID: UUID) -> some View {
        List {
            if room.bills.isEmpty {
                ContentUnavailableView(
                    "No bills yet",
                    systemImage: "doc.text",
                    description: Text("The host adds the receipt before claiming can start.")
                )
            }
            ForEach(room.bills) { bill in
                Section {
                    if bill.items.isEmpty {
                        Text("No items on this bill.").foregroundStyle(.secondary)
                    }
                    ForEach(bill.items) { item in
                        ClaimItemRow(
                            item: item,
                            room: room,
                            actingID: actingID,
                            actingIsHost: actingIsHost,
                            onClaim: { store.claim(itemID: item.id, billID: bill.id, roomID: roomID) },
                            onJoin: { store.joinClaim(itemID: item.id, billID: bill.id, roomID: roomID) },
                            onRelease: { requestRelease(item: item, billID: bill.id) },
                            onForceAssign: { memberID in
                                store.forceAssign(itemID: item.id, billID: bill.id, to: memberID, roomID: roomID)
                            }
                        )
                    }
                } header: {
                    Text(bill.merchantName)
                }
            }
        }
        .navigationTitle("Claim Items")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .safeAreaBar(edge: .bottom) {
            runningTotalCard(room, actingID: actingID)
                .padding(.horizontal)
        }
    }

    private func requestRelease(item: BillItem, billID: UUID) {
        store.releaseClaim(itemID: item.id, billID: billID, roomID: roomID)
    }

    /// Persistent info card in the floating layer (`safeAreaBar`), styled
    /// after the Examples' DemoInfoCard: it informs — every claim action
    /// stays on the item rows it belongs to.
    private func runningTotalCard(_ room: Room, actingID: UUID) -> some View {
        let estimate = room.estimatedClaimSettlement(for: actingID)
        return HStack(alignment: .top, spacing: 8) {
            Image(systemName: "hand.tap")
                .foregroundStyle(.tint)
                .font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text("Your total so far (inc. tax & service)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(estimate.total.rupiah)
                    .font(.headline)
                if estimate.total > 0 {
                    Text("Items: \(estimate.subtotal.rupiah) · Tax: \(estimate.taxShare.rupiah) · Svc: \(estimate.serviceShare.rupiah)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 24))
    }
}

private struct ClaimItemRow: View {
    let item: BillItem
    let room: Room
    let actingID: UUID
    let actingIsHost: Bool
    let onClaim: () -> Void
    let onJoin: () -> Void
    let onRelease: () -> Void
    let onForceAssign: (UUID) -> Void

    private func name(_ id: UUID) -> String {
        room.member(withID: id)?.displayName ?? "someone"
    }

    private var iAmClaimer: Bool {
        if case .claimed(let claims) = item.claimState {
            return claims.contains { $0.memberID == actingID }
        }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(item.name)
                Spacer()
                Text(item.unitPrice.rupiah)
                    .foregroundStyle(.secondary)
            }
            HStack {
                statusLine
                Spacer()
                actionButton
            }
        }
        .padding(.vertical, 2)
        .contextMenu {
            // Host exception power, off the default surface: long-press to
            // assign an item to any member.
            if actingIsHost {
                Menu("Assign to…") {
                    ForEach(room.members) { member in
                        Button {
                            onForceAssign(member.id)
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
    }

    @ViewBuilder
    private var statusLine: some View {
        switch item.claimState {
        case .unclaimed:
            Label("Unclaimed", systemImage: "circle.dashed")
                .font(.caption)
                .foregroundStyle(.orange)
        case .claimed(let claims):
            if claims.count == 1, let only = claims.first {
                Label(
                    only.memberID == actingID ? "Yours" : "Claimed by \(name(only.memberID))",
                    systemImage: "person.fill"
                )
                .font(.caption)
                .foregroundStyle(only.memberID == actingID ? .green : .secondary)
            } else {
                Label(
                    "Shared: " + claims
                        .map { "\(name($0.memberID)) \($0.portion.description)" }
                        .joined(separator: " · "),
                    systemImage: "person.2.fill"
                )
                .font(.caption)
                .foregroundStyle(iAmClaimer ? .green : .secondary)
            }
        case .forceAssigned(let memberID):
            Label("Assigned to \(name(memberID)) by host", systemImage: "hand.point.right.fill")
                .font(.caption)
                .foregroundStyle(.purple)
        }
    }

    /// One explicit trailing button per row — the row's single action.
    @ViewBuilder
    private var actionButton: some View {
        Group {
            switch item.claimState {
            case .unclaimed:
                Button("Claim", action: onClaim)
            case .claimed:
                if iAmClaimer {
                    Button("Release", role: .destructive, action: onRelease)
                } else {
                    Button("Join Split", action: onJoin)
                }
            case .forceAssigned:
                EmptyView()
            }
        }
        .font(.subheadline)
        .buttonStyle(.borderless)
    }
}
