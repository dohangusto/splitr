//
//  PaymentStatusView.swift
//  splitr
//
//  Created by Christian Bryan Seputra on 20/07/26.
//

import SwiftUI
import SplitBillCore

// MARK: - Payment Status View

struct PaymentStatusView: View {
    let store: any RoomStoring
    let roomID: UUID

    @Environment(\.dismiss) private var dismiss
    @State private var showSuccessAnimation = false

    private var room: Room? { store.room(withID: roomID) }
    private var actingID: UUID? { store.actingMemberID(in: roomID) }
    private var isHost: Bool { room?.hostMemberID == actingID }

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
                    // Custom Navigation Header
                    NavigationHeader(
                        title: "Payment Status"
                    )
                    .padding(.horizontal, 24)
                    .padding(.bottom, 28)

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

                                Text(room.name)
                                    .font(
                                        .system(
                                            size: 14,
                                            weight: .semibold,
                                            design: .monospaced
                                        )
                                    )
                                    .frame(
                                        maxWidth: .infinity,
                                        alignment: .center
                                    )
                                    .padding(.vertical, 16)

                                DashedLine()

                                // MARK: Your Items
                                Text("Your item’s")
                                    .font(.system(size: 15))
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 20)

                                VStack(spacing: 20) {
                                    let allItems = room.bills.flatMap(\.items)
                                    if allItems.isEmpty {
                                        Text("No items in receipt")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    } else {
                                        ForEach(allItems) { item in
                                            ReceiptItemRow(
                                                quantity: 1,
                                                name: item.name,
                                                price: item.unitPrice.rupiah,
                                                claimersText: claimersText(for: item, in: room)
                                            )
                                        }
                                    }
                                }
                                .padding(.top, 18)

                                // MARK: Total
                                HStack {
                                    Text("Total")
                                        .font(
                                            .system(
                                                size: 17,
                                                weight: .bold
                                            )
                                        )

                                    Spacer()

                                    let totalAmount = room.bills.map(\.grandTotal).reduce(0, +)
                                    Text(totalAmount.rupiah)
                                        .font(
                                            .system(
                                                size: 17,
                                                weight: .bold
                                            )
                                        )
                                }
                                .padding(.top, 30)

                                // MARK: Payment Status Title
                                VStack(
                                    alignment: .leading,
                                    spacing: 6
                                ) {
                                    Text("Payment Status")
                                        .font(
                                            .system(
                                                size: 18,
                                                weight: .semibold
                                            )
                                        )

                                    Text("Track everyone's payment.")
                                        .font(.system(size: 15))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.top, 32)

                                // MARK: Members List
                                VStack(spacing: 0) {
                                    ForEach(
                                        Array(room.members.enumerated()),
                                        id: \.element.id
                                    ) { index, member in
                                        PaymentMemberRow(
                                            member: member,
                                            isHostView: isHost,
                                            onTogglePaid: {
                                                if isHost && !member.isHost {
                                                    store.confirmPayment(of: member.id, roomID: roomID)
                                                }
                                            }
                                        )

                                        if index < room.members.count - 1 {
                                            Divider().opacity(0.5)
                                        }
                                    }
                                }
                                .padding(.top, 20)
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
                                Text(room.state == .closed ? "Done" : "Make as done")
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
                                        store.markPaid(roomID: roomID)
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
                    .padding(.top, 24)
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
                showSuccessAnimation = false
                dismiss()
            })
        }
    }

    private func claimersText(for item: BillItem, in room: Room) -> String {
        switch item.claimState {
        case .unclaimed:
            return "Unclaimed"
        case .claimed(let claims):
            let names = claims.compactMap { room.member(withID: $0.memberID)?.displayName }
            if names.isEmpty { return "Unclaimed" }
            return "Claimed by " + names.joined(separator: ", ")
        case .forceAssigned(let memberID):
            let name = room.member(withID: memberID)?.displayName ?? "someone"
            return "Assigned to " + name
        }
    }
}

// MARK: - Receipt Item Row

private struct ReceiptItemRow: View {
    let quantity: Int
    let name: String
    let price: String
    let claimersText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 16) {
                Text("x\(quantity)")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(width: 25, alignment: .leading)

                Text(name)
                    .font(
                        .system(
                            size: 16,
                            weight: .medium
                        )
                    )

                Spacer()

                Text(price)
                    .font(
                        .system(
                            size: 16,
                            weight: .medium
                        )
                    )
            }

            Text(claimersText)
                .font(.system(size: 12))
                .foregroundStyle(claimersText == "Unclaimed" ? Color.red.opacity(0.8) : Color.secondary)
                .padding(.leading, 41)
        }
    }
}

// MARK: - Payment Member Row

private struct PaymentMemberRow: View {
    let member: Member
    let isHostView: Bool
    let onTogglePaid: () -> Void

    var body: some View {
        Button {
            onTogglePaid()
        } label: {
            HStack(spacing: 16) {
                // Avatar
                if let uiImage = UIImage(named: member.avatarEmoji) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 48, height: 48)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.gray.opacity(0.15), lineWidth: 1))
                } else {
                    Text(member.avatarEmoji)
                        .font(.system(size: 24))
                        .frame(width: 48, height: 48)
                        .background(Color.gray.opacity(0.1))
                        .clipShape(Circle())
                }

                // Name
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(member.displayName)
                            .font(
                                .system(
                                    size: 16,
                                    weight: .medium
                                )
                            )
                            .foregroundStyle(.primary)

                        if member.isHost {
                            Text("Host")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color("Blue2"))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color("Blue2").opacity(0.12))
                                .clipShape(Capsule())
                        }
                    }
                }

                Spacer()

                // Status Badge: Host is ALWAYS Paid automatically
                PaymentBadge(
                    isPaid: member.isHost || member.paymentStatus == .hostConfirmed || member.paymentStatus == .memberMarkedPaid,
                    isHost: member.isHost,
                    status: member.paymentStatus
                )
            }
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .disabled(!isHostView || member.isHost)
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
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
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
                .padding(.vertical, 40)
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
