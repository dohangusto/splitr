//
//  PaymentStatusView.swift
//  splitr
//
//  Created by Christian Bryan Seputra on 20/07/26.
//

import SwiftUI
import SplitBillCore

// MARK: - Member Breakdown Model

struct MemberBreakdown: Identifiable {
    var id: UUID { member.id }
    let member: Member
    let items: [(name: String, portionText: String, price: Int)]
    let subtotal: Int
    let taxShare: Int
    let serviceShare: Int
    let totalOwed: Int
}

// MARK: - Payment Status View

struct PaymentStatusView: View {
    let store: any RoomStoring
    let roomID: UUID

    @Environment(\.dismiss) private var dismiss
    @State private var showSuccessAnimation = false
    @State private var shareableImage: UIImage?
    @State private var showShareSheet = false

    private var room: Room? { store.room(withID: roomID) }
    private var actingID: UUID? { store.actingMemberID(in: roomID) }
    private var isHost: Bool { room?.hostMemberID == actingID }

    private var memberBreakdowns: [MemberBreakdown] {
        guard let room else { return [] }
        let settlement = try? SettlementCalculator.settle(room: room)

        return room.members.map { member in
            var claimedItems: [(name: String, portionText: String, price: Int)] = []
            for bill in room.bills {
                for item in bill.items {
                    switch item.claimState {
                    case .claimed(let claims):
                        if let c = claims.first(where: { $0.memberID == member.id }) {
                            let portionText = c.portion == .one ? "1x" : "\(c.portion)x (shared)"
                            let portionPrice = (c.portion * item.unitPrice).flooredValue
                            claimedItems.append((name: item.name, portionText: portionText, price: portionPrice))
                        }
                    case .forceAssigned(let id):
                        if id == member.id {
                            claimedItems.append((name: item.name, portionText: "1x", price: item.unitPrice))
                        }
                    case .unclaimed:
                        break
                    }
                }
            }

            let share = settlement?.settlement(for: member.id)
            let estimate = room.estimatedClaimSettlement(for: member.id)

            let subtotal = share?.subtotal ?? estimate.subtotal
            let taxShare = share?.taxShare ?? estimate.taxShare
            let serviceShare = share?.serviceShare ?? estimate.serviceShare
            let totalOwed = share?.totalOwed ?? estimate.total

            return MemberBreakdown(
                member: member,
                items: claimedItems,
                subtotal: subtotal,
                taxShare: taxShare,
                serviceShare: serviceShare,
                totalOwed: totalOwed
            )
        }
    }

    @MainActor
    private func shareReceiptAsImage() {
        guard let room else { return }
        let renderView = TicketReceiptRenderView(room: room, breakdowns: memberBreakdowns)
        let renderer = ImageRenderer(content: renderView)
        renderer.scale = 3.0 // Ultra-crisp 3x Retina
        if let uiImage = renderer.uiImage {
            shareableImage = uiImage
            showShareSheet = true
        }
    }

    var body: some View {
        ZStack {
            // MARK: Background
            Color(
                red: 237 / 255,
                green: 242 / 255,
                blue: 255 / 255
            )
            .ignoresSafeArea()

            if let room {
                // MARK: Main Content
                VStack(spacing: 0) {
                    // Custom Navigation Header with Share Button
                    ZStack(alignment: .trailing) {
                        NavigationHeader(
                            title: "Payment Status"
                        )

                        Button {
                            shareReceiptAsImage()
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.black)
                                .frame(width: 44, height: 44)
                                .background(Color.white)
                                .clipShape(Circle())
                                .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)

                    // MARK: Receipt Card ScrollView
                    ScrollView(
                        .vertical,
                        showsIndicators: false
                    ) {
                        TicketCard {
                            VStack(
                                alignment: .leading,
                                spacing: 0
                            ) {
                                // Invoice Title
                                DashedLine()

                                VStack(spacing: 4) {
                                    Text(room.name)
                                        .font(.system(size: 16, weight: .bold, design: .rounded))
                                        .foregroundStyle(.primary)

                                    let totalAmount = room.bills.map(\.grandTotal).reduce(0, +)
                                    Text("Grand Total: \(totalAmount.rupiah)")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(Color("Blue2"))
                                }
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 16)

                                DashedLine()

                                // MARK: Members Breakdown List
                                VStack(alignment: .leading, spacing: 20) {
                                    Text("Member Breakdown")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundStyle(.primary)
                                        .padding(.top, 16)

                                    ForEach(memberBreakdowns) { detail in
                                        MemberBreakdownCard(
                                            detail: detail,
                                            isHostView: isHost,
                                            onTogglePaid: {
                                                if isHost && !detail.member.isHost {
                                                    store.confirmPayment(of: detail.member.id, roomID: roomID)
                                                }
                                            }
                                        )

                                        if detail.id != memberBreakdowns.last?.id {
                                            Divider().opacity(0.6)
                                        }
                                    }
                                }
                                .padding(.top, 4)

                                // MARK: Share Image Button in Ticket
                                Button {
                                    shareReceiptAsImage()
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "photo.on.rectangle.angled")
                                            .font(.system(size: 14, weight: .semibold))
                                        Text("Share Receipt Image")
                                            .font(.system(size: 14, weight: .semibold))
                                    }
                                    .foregroundColor(Color("Blue2"))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(Color("Blue2").opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                                .buttonStyle(.plain)
                                .padding(.top, 24)
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 30)
                    }

                    // MARK: Bottom Button
                    VStack {
                        if isHost {
                            Button {
                                if room.state != .closed {
                                    store.advance(roomID: roomID)
                                }
                                showSuccessAnimation = true
                            } label: {
                                Text(room.state == .closed ? "Done" : "Mark as done")
                                    .font(
                                        .system(
                                            size: 17,
                                            weight: .medium
                                        )
                                    )
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 56)
                                    .background {
                                        LinearGradient(
                                            colors: [
                                                Color(
                                                    red: 112 / 255,
                                                    green: 158 / 255,
                                                    blue: 255 / 255
                                                ),
                                                Color(
                                                    red: 75 / 255,
                                                    green: 121 / 255,
                                                    blue: 255 / 255
                                                )
                                            ],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    }
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        } else {
                            if let actingID, let me = room.member(withID: actingID) {
                                if me.paymentStatus == .none {
                                    Button {
                                        showSuccessAnimation = true
                                    } label: {
                                        Text("I've Paid")
                                            .font(.system(size: 17, weight: .medium))
                                            .foregroundStyle(.white)
                                            .frame(maxWidth: .infinity)
                                            .frame(height: 56)
                                            .background(
                                                LinearGradient(
                                                    colors: [Color("Blue1"), Color("Blue2")],
                                                    startPoint: .top,
                                                    endPoint: .bottom
                                                )
                                            )
                                            .clipShape(Capsule())
                                    }
                                    .buttonStyle(.plain)
                                } else {
                                    Text("Paid")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(.green)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 56)
                                        .background(Color.green.opacity(0.12))
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .padding(.bottom, 24)
                    .background(
                        Color.white
                            .clipShape(
                                UnevenRoundedRectangle(
                                    topLeadingRadius: 32,
                                    topTrailingRadius: 32
                                )
                            )
                            .ignoresSafeArea(edges: .bottom)
                    )
                }
            } else {
                ContentUnavailableView("Room not found", systemImage: "questionmark.circle")
            }
        }
        .navigationBarBackButtonHidden(true)
        .fullScreenCover(isPresented: $showSuccessAnimation) {
            SuccessAnimationView(onFinished: {
                store.markPaid(roomID: roomID)
                showSuccessAnimation = false
                dismiss()
            })
        }
        .sheet(isPresented: $showShareSheet) {
            if let shareableImage {
                ActivityView(activityItems: [shareableImage])
            }
        }
    }
}

// MARK: - Rendered Ticket View for Image Export

private struct TicketReceiptRenderView: View {
    let room: Room
    let breakdowns: [MemberBreakdown]

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 16) {
                // Header Logo / Branding
                HStack(spacing: 8) {
                    Image(systemName: "receipt.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(Color("Blue2"))
                    Text("Splitr")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(Color("Blue2"))
                }
                .padding(.top, 4)

                DashedLine()

                // Room Name & Grand Total
                VStack(spacing: 4) {
                    Text(room.name)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)

                    let totalAmount = room.bills.map(\.grandTotal).reduce(0, +)
                    Text("Grand Total: \(totalAmount.rupiah)")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color("Blue2"))
                }

                DashedLine()

                // Member Breakdowns
                VStack(alignment: .leading, spacing: 16) {
                    Text("Member Breakdown")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.primary)

                    ForEach(breakdowns) { detail in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                HStack(spacing: 6) {
                                    if let uiImage = UIImage(named: detail.member.avatarEmoji) {
                                        Image(uiImage: uiImage)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 24, height: 24)
                                            .clipShape(Circle())
                                    } else {
                                        Text(detail.member.avatarEmoji)
                                            .font(.system(size: 14))
                                    }

                                    Text(detail.member.displayName)
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundColor(.primary)

                                    if detail.member.isHost {
                                        Text("Host")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundColor(Color("Blue2"))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color("Blue2").opacity(0.12))
                                            .clipShape(Capsule())
                                    }
                                }

                                Spacer()

                                let isPaid = detail.member.isHost || detail.member.paymentStatus == .hostConfirmed || detail.member.paymentStatus == .memberMarkedPaid
                                Text(isPaid ? "Paid" : "Unpaid")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(isPaid ? .green : .orange)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background((isPaid ? Color.green : Color.orange).opacity(0.12))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }

                            if detail.items.isEmpty {
                                Text("No items claimed")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.leading, 28)
                            } else {
                                VStack(spacing: 4) {
                                    ForEach(Array(detail.items.enumerated()), id: \.offset) { _, item in
                                        HStack {
                                            Text("\(item.portionText) \(item.name)")
                                                .font(.system(size: 13))
                                                .foregroundColor(.primary)
                                            Spacer()
                                            Text(item.price.rupiah)
                                                .font(.system(size: 13, weight: .medium))
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                                .padding(.leading, 28)
                            }

                            if detail.taxShare > 0 || detail.serviceShare > 0 {
                                HStack {
                                    Text("Items: \(detail.subtotal.rupiah)")
                                    if detail.serviceShare > 0 {
                                        Text("· Svc: \(detail.serviceShare.rupiah)")
                                    }
                                    if detail.taxShare > 0 {
                                        Text("· Tax: \(detail.taxShare.rupiah)")
                                    }
                                }
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .padding(.leading, 28)
                            }

                            HStack {
                                Spacer()
                                Text("Total: \(detail.totalOwed.rupiah)")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(Color("Blue2"))
                            }
                        }

                        if detail.id != breakdowns.last?.id {
                            Divider().opacity(0.6)
                        }
                    }
                }

                DashedLine()

                // Watermark footer
                HStack(spacing: 4) {
                    Text("Split easily with")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Text("Splitr")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color("Blue2"))
                    Text("🚀")
                        .font(.system(size: 12))
                }
                .padding(.bottom, 6)
            }
            .padding(24)
        }
        .frame(width: 360)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(16)
        .background(Color(red: 237 / 255, green: 242 / 255, blue: 255 / 255))
    }
}

// MARK: - Activity View (Share Sheet)

private struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    let applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: applicationActivities
        )
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Member Breakdown Card

private struct MemberBreakdownCard: View {
    let detail: MemberBreakdown
    let isHostView: Bool
    let onTogglePaid: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Member Header (Avatar, Name, Status)
            HStack(spacing: 12) {
                if let uiImage = UIImage(named: detail.member.avatarEmoji) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 38, height: 38)
                        .clipShape(Circle())
                } else {
                    Text(detail.member.avatarEmoji)
                        .font(.system(size: 20))
                        .frame(width: 38, height: 38)
                        .background(Color.gray.opacity(0.1))
                        .clipShape(Circle())
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(detail.member.displayName)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.primary)

                        if detail.member.isHost {
                            Text("Host")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Color("Blue2"))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color("Blue2").opacity(0.12))
                                .clipShape(Capsule())
                        }
                    }
                }

                Spacer()

                // Status Badge (clickable by host to confirm payment)
                Button {
                    onTogglePaid()
                } label: {
                    PaymentBadge(
                        isPaid: detail.member.isHost || detail.member.paymentStatus == .hostConfirmed || detail.member.paymentStatus == .memberMarkedPaid,
                        isHost: detail.member.isHost,
                        status: detail.member.paymentStatus
                    )
                }
                .buttonStyle(.plain)
                .disabled(!isHostView || detail.member.isHost)
            }

            // Items List
            if detail.items.isEmpty {
                Text("No items claimed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 50)
            } else {
                VStack(spacing: 6) {
                    ForEach(Array(detail.items.enumerated()), id: \.offset) { _, item in
                        HStack {
                            Text("\(item.portionText) \(item.name)")
                                .font(.system(size: 13))
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            Spacer()

                            Text(item.price.rupiah)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.leading, 50)
            }

            // Subtotal, Tax, Svc breakdown if applicable
            if detail.taxShare > 0 || detail.serviceShare > 0 {
                HStack {
                    Text("Items: \(detail.subtotal.rupiah)")
                    if detail.serviceShare > 0 {
                        Text("· Svc: \(detail.serviceShare.rupiah)")
                    }
                    if detail.taxShare > 0 {
                        Text("· Tax: \(detail.taxShare.rupiah)")
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.leading, 50)
            }

            // Member Total
            HStack {
                Spacer()
                Text("Total: \(detail.totalOwed.rupiah)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color("Blue2"))
            }
            .padding(.top, 2)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Payment Badge

private struct PaymentBadge: View {
    let isPaid: Bool
    let isHost: Bool
    let status: PaymentStatus

    var body: some View {
        HStack(spacing: 5) {
            Image(
                systemName: (isHost || status == .hostConfirmed || status == .memberMarkedPaid)
                    ? "checkmark.circle.fill"
                    : "clock.fill"
            )
            .foregroundStyle(
                (isHost || status == .hostConfirmed || status == .memberMarkedPaid)
                    ? Color.green
                    : Color.orange
            )

            Text(
                (isHost || status == .hostConfirmed || status == .memberMarkedPaid)
                    ? "Paid"
                    : "Unpaid"
            )
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.white)
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.gray.opacity(0.25), lineWidth: 1)
        }
    }
}

// MARK: - Dashed Line

private struct DashedLine: View {
    var body: some View {
        Rectangle()
            .stroke(
                Color.gray.opacity(0.7),
                style: StrokeStyle(
                    lineWidth: 1,
                    dash: [5, 5]
                )
            )
            .frame(height: 1)
    }
}

// MARK: - Ticket Card

private struct TicketCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            TicketShape(
                toothWidth: 28,
                toothHeight: 14
            )
            .fill(Color.white)

            content
                .padding(.horizontal, 24)
                .padding(.vertical, 32)
        }
    }
}

// MARK: - Preview

#Preview {
    let store = MockRoomStore(rooms: MockData.rooms())
    NavigationStack {
        PaymentStatusView(store: store, roomID: store.rooms[0].id)
    }
}
