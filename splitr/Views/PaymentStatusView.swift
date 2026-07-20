//
//  PaymentStatusView.swift
//  splitr
//
//  Created by Christian Bryan Seputra on 20/07/26.
//

import SwiftUI


// MARK: - Payment Model

struct PaymentMember: Identifiable {
    let id = UUID()
    let name: String
    let avatar: String
    var isPaid: Bool
}


// MARK: - Payment Status View

struct PaymentStatusView: View {

    @State private var members: [PaymentMember] = [
        PaymentMember(
            name: "Hano Ngoding",
            avatar: "Avatar1",
            isPaid: true
        ),
        PaymentMember(
            name: "Noorfi Github",
            avatar: "Avatar2",
            isPaid: true
        ),
        PaymentMember(
            name: "Husni Ilustrator",
            avatar: "Avatar3",
            isPaid: false
        ),
        PaymentMember(
            name: "Bray Layout",
            avatar: "Avatar4",
            isPaid: false
        )
    ]

    var body: some View {

        ZStack {

            // MARK: Background

            Color(
                red: 237 / 255,
                green: 242 / 255,
                blue: 255 / 255
            )
            .ignoresSafeArea()


            // MARK: Main Content

            VStack(spacing: 0) {

                // Custom Navigation
                NavigationHeader(
                    title: "Payment Status"
                )
                .padding(.horizontal, 24)
                .padding(.bottom, 28)


                // MARK: Receipt Card

                ScrollView(
                    .vertical,
                    showsIndicators: false
                ) {

                    TicketCard {

                        VStack(
                            alignment: .leading,
                            spacing: 0
                        ) {

                            // MARK: Invoice Title

                            DashedLine()

                            Text(
                                "Trip Invoice - Gacoan Yukkk 2026"
                            )
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

                                ReceiptItemRow(
                                    quantity: 1,
                                    name: "Cimory hazelnut",
                                    price: "9,000"
                                )

                                ReceiptItemRow(
                                    quantity: 3,
                                    name: "Cimory choco",
                                    price: "9,000"
                                )
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

                                Text("34,000")
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

                                Text(
                                    "Track everyone's payment."
                                )
                                .font(.system(size: 15))
                                .foregroundStyle(.secondary)
                            }
                            .padding(.top, 32)


                            // MARK: Members

                            VStack(spacing: 0) {

                                ForEach(
                                    Array(members.enumerated()),
                                    id: \.element.id
                                ) { index, member in

                                    PaymentMemberRow(
                                        member: member
                                    )

                                    if index
                                        < members.count - 1 {

                                        Divider()
                                            .opacity(0.5)
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

                    Button {

                        // Mark bill as done

                    } label: {

                        Text("Make as done")
                            .font(
                                .system(
                                    size: 17,
                                    weight: .medium
                                )
                            )
                            .foregroundStyle(.white)
                            .frame(
                                maxWidth: .infinity
                            )
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
                            .clipShape(
                                Capsule()
                            )
                    }
                    .buttonStyle(.plain)
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
        }
        .navigationBarBackButtonHidden(true)
    }
}


// MARK: - Receipt Item Row

private struct ReceiptItemRow: View {

    let quantity: Int
    let name: String
    let price: String

    var body: some View {

        HStack(spacing: 16) {

            Text("x\(quantity)")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(
                    width: 25,
                    alignment: .leading
                )

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
    }
}


// MARK: - Payment Member Row

private struct PaymentMemberRow: View {

    let member: PaymentMember

    var body: some View {

        HStack(spacing: 16) {

            // Avatar

            Image(member.avatar)
                .resizable()
                .scaledToFill()
                .frame(
                    width: 48,
                    height: 48
                )
                .clipShape(Circle())
                .overlay {

                    Circle()
                        .stroke(
                            Color.gray.opacity(0.15),
                            lineWidth: 1
                        )
                }


            // Name

            Text(member.name)
                .font(
                    .system(
                        size: 16,
                        weight: .medium
                    )
                )

            Spacer()


            // Status

            PaymentBadge(
                isPaid: member.isPaid
            )
        }
        .padding(.vertical, 12)
    }
}


// MARK: - Payment Badge

private struct PaymentBadge: View {

    let isPaid: Bool

    var body: some View {

        HStack(spacing: 5) {

            Image(
                systemName:
                    isPaid
                    ? "checkmark.circle.fill"
                    : "clock.fill"
            )
            .foregroundStyle(
                isPaid
                ? Color.green
                : Color.orange
            )

            Text(
                isPaid
                ? "Paid"
                : "Unpaid"
            )
            .font(.system(size: 14))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(Color.white)
        .overlay {

            RoundedRectangle(
                cornerRadius: 5
            )
            .stroke(
                Color.gray.opacity(0.25),
                lineWidth: 1
            )
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

private struct TicketCard<
    Content: View
>: View {

    @ViewBuilder
    let content: Content

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

    NavigationStack {

        PaymentStatusView()
    }
}
