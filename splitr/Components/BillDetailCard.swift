//
//  BillDetailCard.swift
//  splitr
//
//  Created by Christian Bryan Seputra on 18/07/26.
//

import SwiftUI

struct BillDetailCard: View {

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // MARK: Bill Title
            Text("Alfamart bill")
                .font(.title3)
                .foregroundStyle(.secondary)
                .padding(.bottom, 20)

            // MARK: Bill Items
            VStack(spacing: 0) {

                BillItemRow(
                    name: "Cimory hazelnut",
                    quantity: 1,
                    price: "9,000"
                )

                Divider()
                    .padding(.vertical, 16)

                BillItemRow(
                    name: "Cimory hazelnut",
                    quantity: 1,
                    price: "9,000"
                )

                Divider()
                    .padding(.vertical, 16)

                BillItemRow(
                    name: "Cimory hazelnut",
                    quantity: 1,
                    price: "9,000"
                )

                Divider()
                    .padding(.vertical, 16)
            }

            // MARK: Bill Summary
            VStack(spacing: 24) {

                BillSummaryRow(
                    title: "Pajak",
                    value: "8,000"
                )

                BillSummaryRow(
                    title: "Servis",
                    value: "0"
                )

                BillSummaryRow(
                    title: "Diskon",
                    value: "0"
                )

                BillSummaryRow(
                    title: "Subtotal",
                    value: "34,000"
                )
            }

            // MARK: Edit Button
            Button {

            } label: {
                HStack(spacing: 12) {

                    Image(systemName: "pencil")
                        .font(.system(size: 20))

                    Text("Edit details")
                        .font(.headline)
                        .foregroundStyle(.primary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(Color.white)
                .overlay {
                    RoundedRectangle(
                        cornerRadius: 28,
                        style: .continuous
                    )
                    .stroke(
                        Color(.systemGray5),
                        lineWidth: 1
                    )
                }
            }
            .buttonStyle(.plain)
            .padding(.top, 24)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(
            RoundedRectangle(
                cornerRadius: 24,
                style: .continuous
            )
        )
    }
}


// MARK: - Bill Item Row

private struct BillItemRow: View {

    let name: String
    let quantity: Int
    let price: String

    var body: some View {
        HStack {

            Text(name)
                .font(.headline)
                .foregroundStyle(.primary)

            Spacer()

            Text("x\(quantity)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            Text(price)
                .font(.headline)
                .foregroundStyle(.primary)
        }
    }
}


// MARK: - Bill Summary Row

private struct BillSummaryRow: View {

    let title: String
    let value: String

    var body: some View {
        HStack {

            Text(title)
                .font(.body)
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .font(.headline)
                .foregroundStyle(.primary)
        }
    }
}


// MARK: - Preview

#Preview {
    ZStack {
        Color(red: 237/255, green: 242/255, blue: 255/255)
            .ignoresSafeArea()

        ScrollView {
            BillDetailCard()
                .padding(20)
        }
    }
}
