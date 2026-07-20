//
//  BillDetailCard.swift
//  splitr
//
//  Created by Christian Bryan Seputra on 18/07/26.
//

import SwiftUI
import SplitBillCore

/// One bill, rendered from Core. Amounts (tax, service, total) are Core's
/// per-bill computed values — never recomputed here. Editing routes to the
/// existing rate-based edit flow via `onEdit`; the card itself is display.
struct BillDetailCard: View {

    let bill: Bill
    /// Bills are editable only while the room is `.open` (host-only).
    var canEdit: Bool = false
    var onEdit: () -> Void = {}

    /// Core stores one row per claimable unit; for display, identical units
    /// regroup into a "x qty" line like the printed receipt.
    private struct DisplayLine: Identifiable {
        let id = UUID()
        let name: String
        let quantity: Int
        let unitPrice: Int
    }

    private var lines: [DisplayLine] {
        var result: [DisplayLine] = []
        for item in bill.items {
            if let index = result.firstIndex(where: {
                $0.name == item.name && $0.unitPrice == item.unitPrice
            }) {
                let existing = result[index]
                result[index] = DisplayLine(
                    name: existing.name,
                    quantity: existing.quantity + 1,
                    unitPrice: existing.unitPrice
                )
            } else {
                result.append(DisplayLine(name: item.name, quantity: 1, unitPrice: item.unitPrice))
            }
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // MARK: - Bill Title

            Text(bill.merchantName)
                .font(.title3)
                .foregroundStyle(.secondary)
                .padding(.bottom, 20)


            // MARK: - Bill Items

            VStack(spacing: 0) {

                ForEach(lines) { line in

                    BillItemRow(
                        name: line.name,
                        quantity: line.quantity,
                        price: (line.unitPrice * line.quantity).rupiah
                    )

                    if line.id != lines.last?.id {
                        Divider()
                            .padding(.vertical, 16)
                    }
                }
            }

            Divider()
                .padding(.vertical, 16)


            // MARK: - Bill Summary
            // No "Diskon" row: discount is not a Core concept (yet).

            VStack(spacing: 24) {

                SummaryRow(title: "Pajak", value: bill.taxTotal.rupiah)

                SummaryRow(title: "Servis", value: bill.serviceChargeTotal.rupiah)

                SummaryRow(title: "Subtotal", value: bill.grandTotal.rupiah)
            }


            // MARK: - Edit Button

            if canEdit {
                Button {
                    onEdit()
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
                        .stroke(Color(.systemGray5), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .padding(.top, 24)
            }
        }
        .padding(24)
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
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

private struct SummaryRow: View {

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

        Color(
            red: 237/255,
            green: 242/255,
            blue: 255/255
        )
        .ignoresSafeArea()

        ScrollView {

            BillDetailCard(
                bill: MockData.rooms()[0].bills.first ?? Bill(merchantName: "Alfamart bill"),
                canEdit: true
            )
            .padding(20)
        }
    }
}
