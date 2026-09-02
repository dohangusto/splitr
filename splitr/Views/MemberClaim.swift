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
    let targetMemberID: UUID
    let interactive: Bool
    let onToggle: () -> Void
    var onManageClaimers: (() -> Void)? = nil

    /// The checkbox reflects whether the target member is on this item.
    private var iAmIn: Bool { item.involves(targetMemberID) }

    /// Who's on the item — the roster, so sharing is never a blind on/off.
    private var statusText: String? {
        switch item.claimState {
        case .unclaimed:
            return nil
        case .claimed(let claims):
            let others = claims
                .map(\.memberID)
                .filter { $0 != targetMemberID }
                .map { room.member(withID: $0)?.displayName ?? "someone" }
            let targetName = room.member(withID: targetMemberID)?.displayName ?? "You"
            if others.isEmpty {
                return targetMemberID == room.hostMemberID ? "Yours" : "Claimed by \(targetName)"
            }
            let names = others.joined(separator: ", ")
            return iAmIn ? "Shared with \(names)" : "Shared: \(names)"
        case .forceAssigned(let memberID):
            let name = room.member(withID: memberID)?.displayName ?? "someone"
            return memberID == targetMemberID ? "Assigned to \(name)" : "Assigned to \(name)"
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
                    .disabled(!interactive)
                    .opacity(interactive ? 1 : 0.5)
            }

            //who's in + price
            HStack(alignment: .center) {
                Button {
                    onManageClaimers?()
                } label: {
                    if let statusText {
                        HStack(spacing: 6) {
                            // Overlapping Avatar Group on the left
                            HStack(spacing: -6) {
                                ForEach(item.participantIDs, id: \.self) { memberID in
                                    if let member = room.member(withID: memberID) {
                                        Group {
                                            if let uiImage = UIImage(named: member.avatarEmoji) {
                                                Image(uiImage: uiImage)
                                                    .resizable()
                                                    .scaledToFill()
                                            } else {
                                                Text(member.avatarEmoji)
                                                    .font(.system(size: 11))
                                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                                    .background(Color(.systemGray6))
                                            }
                                        }
                                        .frame(width: 20, height: 20)
                                        .clipShape(Circle())
                                        .overlay {
                                            Circle()
                                                .stroke(Color.white, lineWidth: 1.5)
                                        }
                                    }
                                }
                            }

                            // Status text on the right
                            Text(statusText)
                                .font(.caption)
                                .foregroundColor(iAmIn ? Color("Blue2") : .secondary)
                                .lineLimit(1)
                        }
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "person.badge.plus")
                                .font(.caption2)
                            Text("Unclaimed · Tap to assign")
                                .font(.caption)
                        }
                        .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)

                Spacer()
                let splitPrice = item.unitPrice / max(1, item.claimState.claimerIDs.count)
                Text(splitPrice.rupiah)
                    .font(.subheadline)
            }
        }
        .padding(.vertical, 22)
    }
}

//MARK: Sheet for assigning/sharing an item among room members
private struct ItemClaimersSheet: View {
    let item: BillItem
    let billID: UUID
    let room: Room
    let store: any RoomStoring
    let roomID: UUID
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.name)
                                .font(.headline)
                            Text(item.unitPrice.rupiah)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        let count = item.claimState.claimerIDs.count
                        if count > 0 {
                            let splitPrice = item.unitPrice / count
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("\(splitPrice.rupiah) / person")
                                    .font(.subheadline.bold())
                                    .foregroundColor(Color("Blue2"))
                                Text("\(count) person\(count == 1 ? "" : "s")")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Select members sharing this item") {
                    ForEach(room.members) { member in
                        let isMemberIn = item.involves(member.id)
                        Button {
                            store.toggleClaim(itemID: item.id, billID: billID, for: member.id, roomID: roomID)
                        } label: {
                            HStack(spacing: 12) {
                                Group {
                                    if let uiImage = UIImage(named: member.avatarEmoji) {
                                        Image(uiImage: uiImage)
                                            .resizable()
                                            .scaledToFill()
                                    } else {
                                        Text(member.avatarEmoji)
                                            .font(.system(size: 16))
                                    }
                                }
                                .frame(width: 36, height: 36)
                                .clipShape(Circle())

                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 4) {
                                        Text(member.displayName)
                                            .font(.body)
                                            .foregroundColor(.primary)
                                        if member.isHost {
                                            Text("Host")
                                                .font(.caption2.bold())
                                                .foregroundColor(.white)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color("Blue2"))
                                                .clipShape(Capsule())
                                        }
                                    }
                                }

                                Spacer()

                                CheckboxButton(isChecked: isMemberIn) {
                                    store.toggleClaim(itemID: item.id, billID: billID, for: member.id, roomID: roomID)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Assign Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
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
    @State private var navigateToPaymentStatus = false
    @State private var showSuccessAnimation = false
    @State private var selectedMemberID: UUID?
    @State private var itemForAssigning: (item: BillItem, billID: UUID)?
    @State private var showAddMemberSheet = false

    private var room: Room? { store.room(withID: roomID) }
    private var actingID: UUID? { store.actingMemberID(in: roomID) }
    private var actingIsHost: Bool { actingID == room?.hostMemberID }
    private var effectiveMemberID: UUID {
        (actingIsHost ? (selectedMemberID ?? actingID) : actingID) ?? UUID()
    }

    var body: some View {
        Group {
            if let room, let actingID {
                content(room, actingID: actingID)
            } else {
                ContentUnavailableView("Room not found", systemImage: "questionmark.circle")
            }
        }
        .background(Color(red: 0.90, green: 0.92, blue: 0.99).ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .navigationDestination(isPresented: $navigateToPaymentStatus) {
            PaymentStatusView(store: store, roomID: roomID)
        }
        .fullScreenCover(isPresented: $showSuccessAnimation) {
            SuccessAnimationView(onFinished: {
                store.markPaid(roomID: roomID)
                showSuccessAnimation = false
                dismiss()
            })
        }
        .sheet(item: Binding(
            get: { itemForAssigning.map { IdentifiableItemWrapper(item: $0.item, billID: $0.billID) } },
            set: { itemForAssigning = $0.map { ($0.item, $0.billID) } }
        )) { wrapper in
            if let room {
                // Find latest item from state
                let currentItem = room.bills.first(where: { $0.id == wrapper.billID })?.items.first(where: { $0.id == wrapper.item.id }) ?? wrapper.item
                ItemClaimersSheet(
                    item: currentItem,
                    billID: wrapper.billID,
                    room: room,
                    store: store,
                    roomID: roomID
                )
            }
        }
        .sheet(isPresented: $showAddMemberSheet) {
            JoinMemberView(store: store, roomID: roomID)
        }
    }

    @ViewBuilder
    private func content(_ room: Room, actingID: UUID) -> some View {
        switch room.state {
        case .open:
            waitingState(room, actingID: actingID)
        case .claiming, .settling, .closed:
            VStack(spacing: 0) {
                ZStack(alignment: .top) {
                    billList(room, actingID: actingID, interactive: room.state != .closed)

                    VStack(spacing: 0) {
                        ZStack(alignment: .trailing) {
                            NavigationHeader(title: "Claim Item")

                            if room.state == .settling || room.state == .closed {
                                Button {
                                    navigateToPaymentStatus = true
                                } label: {
                                    Image(systemName: "creditcard")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.black)
                                        .frame(width: 44, height: 44)
                                        .background(Color.white)
                                        .clipShape(Circle())
                                        .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
                                }
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 10)
                        .padding(.bottom, 8)
                        .background(Color(red: 0.90, green: 0.92, blue: 0.99).ignoresSafeArea(edges: .top))

                        if actingIsHost && room.state != .closed {
                            memberSelectorBar(room)
                                .background(Color(red: 0.90, green: 0.92, blue: 0.99))
                        }

                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color(red: 0.90, green: 0.92, blue: 0.99),
                                Color(red: 0.90, green: 0.92, blue: 0.99).opacity(0)
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 20)
                    }
                }

                footer(room, actingID: actingID)
            }
        }
    }

    // MARK: - Member Selector Bar (Host Manual Claiming)

    @ViewBuilder
    private func memberSelectorBar(_ room: Room) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(room.members) { member in
                    let isSelected = member.id == effectiveMemberID
                    Button {
                        selectedMemberID = member.id
                    } label: {
                        HStack(spacing: 6) {
                            Group {
                                if let uiImage = UIImage(named: member.avatarEmoji) {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .scaledToFill()
                                } else {
                                    Text(member.avatarEmoji)
                                        .font(.system(size: 12))
                                }
                            }
                            .frame(width: 22, height: 22)
                            .clipShape(Circle())

                            Text(member.id == room.hostMemberID ? "\(member.displayName) (You)" : member.displayName)
                                .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                                .foregroundColor(isSelected ? .white : .primary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            isSelected ?
                            AnyShapeStyle(
                                LinearGradient(
                                    colors: [Color("Blue1"), Color("Blue2")],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            ) :
                            AnyShapeStyle(Color.white)
                        )
                        .clipShape(Capsule())
                        .shadow(color: .black.opacity(isSelected ? 0.15 : 0.04), radius: 4, y: 2)
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    showAddMemberSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                        Text("Add Member")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(Color("Blue2"))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.white)
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 4)
        }
    }

    // MARK: - Waiting Room (room still .open)

    private func waitingState(_ room: Room, actingID: UUID) -> some View {
        let me = room.member(withID: actingID)
        let host = room.member(withID: room.hostMemberID)
        
        return VStack(spacing: 0) {
            // Header
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)
                        .frame(width: 40, height: 40)
                        .background(Color.white)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
                }
                Spacer()
                Text("Waiting Room")
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()
                Color.clear.frame(width: 40, height: 40)
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 16)
            
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 24) {
                    // Room Info Card
                    VStack(spacing: 12) {
                        Text(room.name)
                            .font(.title2.bold())
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.center)
                        
                        if let host {
                            HStack(spacing: 6) {
                                Group {
                                    if let uiImage = UIImage(named: host.avatarEmoji) {
                                        Image(uiImage: uiImage)
                                            .resizable()
                                            .scaledToFill()
                                    } else {
                                        Text(host.avatarEmoji)
                                            .font(.system(size: 14))
                                    }
                                }
                                .frame(width: 24, height: 24)
                                .clipShape(Circle())
                                
                                Text("Hosted by \(host.displayName)")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color(red: 0.94, green: 0.95, blue: 0.99))
                            .clipShape(Capsule())
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .shadow(color: .black.opacity(0.04), radius: 10, y: 3)
                    
                    // Animated Waiting Card
                    VStack(spacing: 18) {
                        ZStack {
                            Circle()
                                .fill(Color("Blue1").opacity(0.12))
                                .frame(width: 90, height: 90)
                            
                            Circle()
                                .fill(Color("Blue1").opacity(0.25))
                                .frame(width: 68, height: 68)
                            
                            Image(systemName: "hourglass")
                                .font(.system(size: 30, weight: .bold))
                                .foregroundColor(Color("Blue2"))
                        }
                        .padding(.top, 8)
                        
                        VStack(spacing: 8) {
                            Text("Waiting for Host")
                                .font(.title3.bold())
                                .foregroundColor(.primary)
                            
                            Text("The host is preparing the bill. Once the host starts claiming, the bill items will appear here automatically.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 8)
                        }
                        
                        Divider()
                            .padding(.vertical, 4)
                        
                        // Your Identity
                        if let me {
                            HStack(spacing: 12) {
                                Group {
                                    if let uiImage = UIImage(named: me.avatarEmoji) {
                                        Image(uiImage: uiImage)
                                            .resizable()
                                            .scaledToFill()
                                    } else {
                                        Text(me.avatarEmoji)
                                            .font(.system(size: 18))
                                    }
                                }
                                .frame(width: 36, height: 36)
                                .clipShape(Circle())
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("You joined as")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(me.displayName)
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                }
                                Spacer()
                                Label("Joined", systemImage: "checkmark.circle.fill")
                                    .font(.caption.bold())
                                    .foregroundColor(.green)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color.green.opacity(0.12))
                                    .clipShape(Capsule())
                            }
                            .padding(12)
                            .background(Color(red: 0.96, green: 0.97, blue: 1.0))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(20)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .shadow(color: .black.opacity(0.04), radius: 10, y: 3)
                    
                    // Members in Room Card
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("Members in Room")
                                .font(.headline)
                                .foregroundColor(.primary)
                            Spacer()
                            Text("\(room.members.count)")
                                .font(.subheadline.bold())
                                .foregroundColor(Color("Blue2"))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color("Blue1").opacity(0.15))
                                .clipShape(Capsule())
                        }
                        
                        ForEach(room.members) { member in
                            HStack(spacing: 12) {
                                Group {
                                    if let uiImage = UIImage(named: member.avatarEmoji) {
                                        Image(uiImage: uiImage)
                                            .resizable()
                                            .scaledToFill()
                                    } else {
                                        Text(member.avatarEmoji)
                                            .font(.system(size: 16))
                                    }
                                }
                                .frame(width: 32, height: 32)
                                .clipShape(Circle())
                                
                                Text(member.id == actingID ? "\(member.displayName) (You)" : member.displayName)
                                    .font(.system(size: 14, weight: member.id == actingID ? .bold : .medium))
                                    .foregroundColor(.primary)
                                
                                Spacer()
                                
                                if member.isHost {
                                    Text("Host")
                                        .font(.caption.bold())
                                        .foregroundColor(.orange)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Color.orange.opacity(0.12))
                                        .clipShape(Capsule())
                                } else {
                                    Text("Member")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .shadow(color: .black.opacity(0.04), radius: 10, y: 3)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
        }
        .background(Color(red: 0.90, green: 0.92, blue: 0.99).ignoresSafeArea())
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
            .padding(.top, 80) // Push content below the header
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
                        targetMemberID: effectiveMemberID,
                        interactive: interactive,
                        onToggle: {
                            store.toggleClaim(itemID: item.id, billID: bill.id, for: effectiveMemberID, roomID: roomID)
                        },
                        onManageClaimers: {
                            itemForAssigning = (item, bill.id)
                        }
                    )
                    .padding(.horizontal)
                    DashedDivider()
                        .padding(.horizontal)
                }

                // MARK: summary rows — Core's per-bill amounts
                VStack(spacing: 12) {
                    summaryRow(label: "Items Subtotal", value: bill.subtotal)
                    if bill.serviceChargeTotal > 0 {
                        summaryRow(label: "Service", value: bill.serviceChargeTotal)
                    }
                    if bill.taxTotal > 0 {
                        summaryRow(label: "Tax (PB1)", value: bill.taxTotal)
                    }
                    summaryRow(label: "Grand Total", value: bill.grandTotal, weight: .semibold)
                }
                .padding()
            }
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
    }

    // MARK: - Bottom Sticky Footer

    /// Claiming: running total including proportional tax & service.
    /// Settling: the Core-computed total owed and the member's "I've Paid" action.
    @ViewBuilder
    private func footer(_ room: Room, actingID: UUID) -> some View {
        let me = room.member(withID: actingID)
        let targetID = effectiveMemberID
        let targetMember = room.member(withID: targetID)
        let estimate = room.estimatedClaimSettlement(for: targetID)
        let owed = (try? SettlementCalculator.settle(room: room))?
            .settlement(for: targetID)?.totalOwed

        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                switch room.state {
                case .claiming:
                    if estimate.total > 0 {
                        let memberLabel = (targetID == actingID) ? "Your" : "\(targetMember?.displayName ?? "Member")'s"
                        HStack(spacing: 4) {
                            Text("\(memberLabel) items: \(estimate.subtotal.rupiah)")
                            if estimate.serviceShare > 0 {
                                Text("· Svc: \(estimate.serviceShare.rupiah)")
                            }
                            if estimate.taxShare > 0 {
                                Text("· Tax: \(estimate.taxShare.rupiah)")
                            }
                        }
                        .font(.caption2)
                        .foregroundColor(.secondary)

                        Text(estimate.total.rupiah)
                            .font(.title3.bold())
                            .foregroundColor(.primary)
                    } else {
                        let memberLabel = (targetID == actingID) ? "your items" : "items for \(targetMember?.displayName ?? "member")"
                        Text("Select \(memberLabel)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(0.rupiah)
                            .font(.title3.bold())
                            .foregroundColor(.primary)
                    }
                default:
                    Text(targetID == actingID ? "You owe the host" : "\(targetMember?.displayName ?? "Member") owes")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text((owed ?? estimate.total).rupiah)
                        .font(.title3.bold())
                        .foregroundColor(.primary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if room.state == .claiming || room.state == .open {
                if actingID == room.hostMemberID {
                    Button(action: {
                        if room.state == .open {
                            store.advance(roomID: roomID)
                        }
                        store.advance(roomID: roomID)
                        navigateToPaymentStatus = true
                    }) {
                        Text("Confirmation")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(width: 140)
                            .padding(.vertical, 14)
                            .background(
                                LinearGradient(
                                    colors: [Color("Blue1"), Color("Blue2")],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .clipShape(Capsule())
                    }
                } else if let me {
                    if me.paymentStatus == .none {
                        Button(action: {
                            showSuccessAnimation = true
                        }) {
                            Text("I've Paid")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(width: 140)
                                .padding(.vertical, 14)
                                .background(
                                    LinearGradient(
                                        colors: [Color("Blue1"), Color("Blue2")],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .clipShape(Capsule())
                        }
                    } else {
                        Text(me.paymentStatus == .hostConfirmed ? "Settled" : "Paid")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(width: 140)
                            .padding(.vertical, 14)
                            .background(Color.green)
                            .clipShape(Capsule())
                    }
                }
            } else if room.state == .settling, let me {
                switch me.paymentStatus {
                case .none:
                    Button(action: {
                        showSuccessAnimation = true
                    }) {
                        Text("I've Paid")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(width: 140)
                            .padding(.vertical, 14)
                            .background(
                                LinearGradient(
                                    colors: [Color("Blue1"), Color("Blue2")],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .clipShape(Capsule())
                    }
                case .memberMarkedPaid, .hostConfirmed:
                    Text("Paid")
                        .font(.subheadline.bold())
                        .foregroundColor(.green)
                        .frame(width: 140)
                        .padding(.vertical, 14)
                        .background(Color.green.opacity(0.1))
                        .clipShape(Capsule())
                }
            } else if room.state == .closed, let me, !me.isHost {
                Text(me.paymentStatus == .hostConfirmed ? "Settled" : "Closed")
                    .font(.subheadline.bold())
                    .foregroundColor(me.paymentStatus == .hostConfirmed ? .green : .secondary)
                    .frame(width: 140)
                    .padding(.vertical, 14)
                    .background(Color.gray.opacity(0.1))
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .background(
            Color.white
                .clipShape(RoundedCorner(radius: 24, corners: [.topLeft, .topRight]))
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

    // helper for Tax/Service/Subtotal rows
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

private struct IdentifiableItemWrapper: Identifiable {
    var id: UUID { item.id }
    let item: BillItem
    let billID: UUID
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
