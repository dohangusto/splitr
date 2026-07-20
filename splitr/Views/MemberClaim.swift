//
//  MemberClaim.swift
//  splitr
//
//  Created by Muhammad Husni Romdhoni on 17/07/26.
//

import SwiftUI
import UIKit
import SplitBillCore

struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

struct DashedDivider: View {
    var color: Color = Color.gray.opacity(0.4)
    var dash: [CGFloat] = [6, 4] // Angka pertama panjang line, angka kedua jarak antar line

    var body: some View {
        Line()
            .stroke(style: StrokeStyle(lineWidth: 1, dash: dash))
            .foregroundColor(color)
            .frame(height: 1)
    }
}

struct CheckboxButton: View {
    let isChecked: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 6)
                .fill(
                    isChecked ?
                    AnyShapeStyle(
                        LinearGradient(
                            colors: [Color("Blue1"), Color("Blue2")],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    ) :
                    AnyShapeStyle(Color(.systemGray5))
                )
                .frame(width: 24, height: 24)
                .overlay {
                    if isChecked {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
        }
        .buttonStyle(.plain)
    }
}

//MARK: view pas expanded
private struct MenuItemRow: View {
    let item: BillItem
    let room: Room
    let actingID: UUID
    let interactive: Bool
    let onToggle: () -> Void

    /// The checkbox is self-only: checked means "I'm on this item".
    private var iAmIn: Bool { item.involves(actingID) }

    /// Exclusive item someone else holds, or a host assignment — the member
    /// can't act on it. Shared items stay joinable no matter who's on them.
    private var locked: Bool {
        (item.isExclusivelyClaimed && !iAmIn) || item.isForceAssigned
    }

    /// Who's on the item — the roster, so sharing is never a blind on/off.
    private var statusText: String? {
        switch item.claimState {
        case .unclaimed:
            return nil
        case .claimed(let claims):
            let others = claims
                .map(\.memberID)
                .filter { $0 != actingID }
                .map { room.member(withID: $0)?.displayName ?? "someone" }
            if others.isEmpty { return "Yours" }
            let names = others.joined(separator: ", ")
            return iAmIn ? "Shared with \(names)" : (item.isSharedClaim ? "Shared: \(names)" : "Claimed by \(names)")
        case .forceAssigned(let memberID):
            let name = room.member(withID: memberID)?.displayName ?? "someone"
            return memberID == actingID ? "Assigned to you by host" : "Assigned to \(name) by host"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            //item + check
            HStack {
                Text(item.name)
                    .font(.subheadline)
                Spacer()
                CheckboxButton(isChecked: iAmIn, action: onToggle)
                    .disabled(!interactive || locked)
                    .opacity(interactive && !locked ? 1 : 0.5)
            }

            //who's in + price
            HStack {
                if let statusText {
                    Text(statusText)
                        .font(.caption)
                        .foregroundColor(iAmIn ? Color("Blue2") : .secondary)
                } else {
                    Text("Unclaimed")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text(item.unitPrice.rupiah)
                    .font(.subheadline)
            }
        }
        .padding(.vertical, 22)
    }
}

//MARK: view utama (dinamis)
/// The covered member's whole world: claim what's mine, see who shares what,
/// and — once settling starts — confirm "I've paid". Reads the same Room /
/// Bill / claim state the host's surface reads; only the slice differs.
struct MemberClaim: View {
    let store: any RoomStoring
    let roomID: UUID

    @Environment(\.dismiss) private var dismiss
    @State private var collapsedBillIDs: Set<UUID> = []
    /// Set when releasing an item shared by several members: warn first.
    @State private var sharedReleaseTarget: (itemID: UUID, billID: UUID)?
    @State private var showSharedReleaseConfirm = false

    private var room: Room? { store.room(withID: roomID) }
    private var actingID: UUID? { store.actingMemberID(in: roomID) }

    var body: some View {
        Group {
            if let room, let actingID {
                content(room, actingID: actingID)
            } else {
                ContentUnavailableView("Room not found", systemImage: "questionmark.circle")
            }
        }
        .background(Color(red: 0.90, green: 0.92, blue: 0.99).ignoresSafeArea())
        .navigationTitle(room?.name ?? "Split bill")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .foregroundColor(.black)
                        .padding(10)
                        .background(Color.white)
                        .clipShape(Circle())
                }
            }
        }
    }

    @ViewBuilder
    private func content(_ room: Room, actingID: UUID) -> some View {
        switch room.state {
        case .open:
            // The host is still adding and editing bills — prices aren't
            // final, so no provisional items are shown at all.
            waitingState
        case .claiming, .settling, .closed:
            VStack(spacing: 0) {
                billList(room, actingID: actingID, interactive: room.state == .claiming)
                footer(room, actingID: actingID)
            }
        }
    }

    // MARK: - Waiting (room still .open)

    private var waitingState: some View {
        VStack(spacing: 16) {
            Image(systemName: "hourglass")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("The host is still preparing the bill")
                .font(.headline)
            Text("You'll claim your items here once claiming opens.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Bills

    private func billList(_ room: Room, actingID: UUID, interactive: Bool) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                ForEach(room.bills) { bill in
                    billCard(bill, room: room, actingID: actingID, interactive: interactive)
                }
            }
            .padding()
        }
        .confirmationDialog(
            "Release this shared item?",
            isPresented: $showSharedReleaseConfirm,
            titleVisibility: .visible
        ) {
            Button("Release for Everyone", role: .destructive) {
                if let target = sharedReleaseTarget {
                    store.releaseClaim(itemID: target.itemID, billID: target.billID, roomID: roomID)
                }
                sharedReleaseTarget = nil
            }
            Button("Cancel", role: .cancel) { sharedReleaseTarget = nil }
        } message: {
            Text("This item is split with others. Releasing it returns the whole item to unclaimed for all sharers.")
        }
    }

    private func billCard(_ bill: Bill, room: Room, actingID: UUID, interactive: Bool) -> some View {
        let isExpanded = !collapsedBillIDs.contains(bill.id)
        return VStack(spacing: 0) {
            // MARK: header disclosure
            Button {
                if isExpanded {
                    collapsedBillIDs.insert(bill.id)
                } else {
                    collapsedBillIDs.remove(bill.id)
                }
            } label: {
                HStack {
                    Text(bill.merchantName)
                        .font(.title3)
                        .bold(true)
                        .foregroundStyle(Color.primary)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .foregroundStyle(Color.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.top)
            .padding(.bottom, isExpanded ? 8 : 20)

            if isExpanded {
                // list item + dashed divider
                ForEach(bill.items) { item in
                    MenuItemRow(
                        item: item,
                        room: room,
                        actingID: actingID,
                        interactive: interactive,
                        onToggle: { toggle(item: item, billID: bill.id, actingID: actingID) }
                    )
                    .padding(.horizontal)
                    DashedDivider()
                        .padding(.horizontal)
                }

                // MARK: summary rows — Core's per-bill amounts, never
                // recomputed here. (No discount row: not a Core concept yet.)
                VStack(spacing: 12) {
                    summaryRow(label: "Pajak", value: bill.taxTotal)
                    summaryRow(label: "Servis", value: bill.serviceChargeTotal)
                    summaryRow(label: "Subtotal", value: bill.grandTotal, weight: .semibold)
                }
                .padding()
            }
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
    }

    /// Self-only toggle: I'm in / I'm out. Never assigns anyone else.
    private func toggle(item: BillItem, billID: UUID, actingID: UUID) {
        switch item.claimState {
        case .unclaimed:
            store.claim(itemID: item.id, billID: billID, roomID: roomID)
        case .claimed(let claims):
            if claims.contains(where: { $0.memberID == actingID }) {
                if claims.count > 1 {
                    sharedReleaseTarget = (item.id, billID)
                    showSharedReleaseConfirm = true
                } else {
                    store.releaseClaim(itemID: item.id, billID: billID, roomID: roomID)
                }
            } else {
                store.joinClaim(itemID: item.id, billID: billID, roomID: roomID)
            }
        case .forceAssigned:
            break // host's call; the row is disabled anyway
        }
    }

    // MARK: - Bottom Sticky Footer

    /// Claiming: running total only — claims commit per toggle, so there is
    /// no confirm button. Settling: the Core-computed total owed and the
    /// member's one remaining action, "I've Paid". Closed: read-only total.
    @ViewBuilder
    private func footer(_ room: Room, actingID: UUID) -> some View {
        let me = room.member(withID: actingID)
        let owed = (try? SettlementCalculator.settle(room: room))?
            .settlement(for: actingID)?.totalOwed

        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                switch room.state {
                case .claiming:
                    Text("Your \(room.claims(for: actingID).count) item total · before tax & service")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text(room.claimedSubtotal(for: actingID).rupiah)
                        .font(.title.bold())
                        .foregroundColor(.primary)
                default:
                    Text("You owe the host")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text((owed ?? room.claimedSubtotal(for: actingID)).rupiah)
                        .font(.title.bold())
                        .foregroundColor(.primary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)

            if room.state == .settling, let me {
                switch me.paymentStatus {
                case .none:
                    Button(action: { store.markPaid(roomID: roomID) }) {
                        Text("I've Paid")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                LinearGradient(
                                    colors: [Color("Blue1"), Color("Blue2")],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .clipShape(Capsule())
                    }
                case .memberMarkedPaid:
                    paymentStatusLine("Waiting for the host to confirm", color: .orange)
                case .hostConfirmed:
                    paymentStatusLine("Settled", color: .green)
                }
            } else if room.state == .closed, let me, !me.isHost {
                paymentStatusLine(
                    me.paymentStatus == .hostConfirmed ? "Settled" : "Room closed",
                    color: me.paymentStatus == .hostConfirmed ? .green : .secondary
                )
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 12) // Penyeimbang padding agar menyatu dengan safe area bottom
        .background(
            Color.white
                .clipShape(RoundedCorner(radius: 32, corners: [.topLeft, .topRight]))
                .ignoresSafeArea(edges: .bottom)
        )
        .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: -5)
    }

    private func paymentStatusLine(_ text: String, color: Color) -> some View {
        Label(text, systemImage: "checkmark.circle.fill")
            .font(.headline)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
    }

    // helper buat baris Pajak/Servis/Subtotal
    @ViewBuilder
    private func summaryRow(label: String, value: Int, weight: Font.Weight = .regular) -> some View {
        HStack {
            Text(label)
                .foregroundColor(weight != .regular ? .primary : .secondary)
            Spacer()
            Text(value.rupiah)
        }
        .font(weight != .regular ? .headline : .subheadline)
        .fontWeight(weight)
    }
}

// Shape kustom untuk membulatkan sudut tertentu (hanya atas kiri & atas kanan)
struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius))
        return Path(path.cgPath)
    }
}

#Preview {
    let store = MockRoomStore(rooms: MockData.rooms())
    let room = store.rooms.first { $0.state == .claiming } ?? store.rooms[0]
    if let member = room.members.first(where: { !$0.isHost }) {
        store.setActingMember(member.id, in: room.id)
    }
    return NavigationStack {
        MemberClaim(store: store, roomID: room.id)
    }
}
