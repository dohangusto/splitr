//
//  BillDetailCard.swift
//  splitr
//
//  Created by Christian Bryan Seputra on 18/07/26.
//

import SwiftUI
import SplitBillCore

/// One bill, rendered from Core. Amounts (tax, service, total) are Core's
/// per-bill computed values — never recomputed here. Host editing happens
/// inline on the bill card itself while the room is still open.
struct BillDetailCard: View {

    let store: any RoomStoring
    let roomID: UUID
    let bill: Bill
    /// Bills are editable only while the room is `.open` (host-only).
    var canEdit: Bool = false

    @State private var isEditing = false
    @State private var merchant = ""
    @State private var taxPercent = 0
    @State private var servicePercent = 0
    @State private var taxBasis: TaxBasis = .subtotalPlusService
    @State private var items: [DraftItem] = []

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

    private var validItems: [DraftItem] {
        items.filter {
            !$0.name.trimmingCharacters(in: .whitespaces).isEmpty && ($0.price ?? 0) > 0
        }
    }

    private var subtotal: Int {
        validItems.reduce(0) { $0 + ($1.price ?? 0) * $1.qty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isEditing {
                editHeader
                Divider()
                    .padding(.vertical, 16)
                editBody
            } else {
                readOnlyBody
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
        .onAppear(perform: populateDraftsIfNeeded)
    }

    private var readOnlyBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(bill.merchantName)
                .font(.title3)
                .foregroundStyle(.secondary)
                .padding(.bottom, 20)

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

            VStack(spacing: 24) {
                SummaryRow(title: "Tax", value: bill.taxTotal.rupiah)
                SummaryRow(title: "Service", value: bill.serviceChargeTotal.rupiah)
                SummaryRow(title: "Subtotal", value: bill.grandTotal.rupiah)
            }

            if canEdit {
                Button {
                    enterEditMode()
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
    }

    private var editHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit bill")
                .font(.title3)
                .foregroundStyle(.secondary)

            TextField("Merchant name", text: $merchant)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var editBody: some View {
        VStack(spacing: 24) {
            VStack(spacing: 16) {
                ForEach($items) { $item in
                    DraftItemRow(item: $item)
                        .contextMenu {
                            Button(role: .destructive) {
                                items.removeAll { $0.id == item.id }
                            } label: {
                                Label("Delete Item", systemImage: "trash")
                            }
                        }
                }

                Button {
                    items.append(DraftItem())
                } label: {
                    Label("Add Item", systemImage: "plus.circle")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

            VStack(spacing: 16) {
                Stepper("PB1 tax: \(taxPercent)%", value: $taxPercent, in: 0...20)
                Stepper("Service charge: \(servicePercent)%", value: $servicePercent, in: 0...15)
                Picker("Tax applies to", selection: $taxBasis) {
                    Text("Subtotal + service").tag(TaxBasis.subtotalPlusService)
                    Text("Subtotal only").tag(TaxBasis.subtotal)
                }
                .pickerStyle(.menu)
            }

            VStack(spacing: 16) {
                SummaryRow(title: "Subtotal", value: subtotal.rupiah)
            }

            HStack(spacing: 12) {
                Button("Cancel") {
                    isEditing = false
                }
                .buttonStyle(.bordered)
                .tint(.secondary)

                Button("Save") {
                    saveEdits()
                }
                .buttonStyle(.borderedProminent)
                .disabled(merchant.trimmingCharacters(in: .whitespaces).isEmpty || validItems.isEmpty)
            }
        }
    }

    private func enterEditMode() {
        merchant = bill.merchantName
        taxPercent = bill.taxRate.basisPoints / 100
        servicePercent = bill.serviceChargeRate.basisPoints / 100
        taxBasis = bill.taxBasis
        items = Self.drafts(from: bill)
        isEditing = true
    }

    private func saveEdits() {
        var updated = bill
        updated.merchantName = merchant.trimmingCharacters(in: .whitespaces)
        updated.taxRate = .percent(taxPercent)
        updated.serviceChargeRate = .percent(servicePercent)
        updated.taxBasis = taxBasis
        updated.items = validItems.flatMap { draft in
            (0..<draft.qty).map { _ in
                BillItem(
                    name: draft.name.trimmingCharacters(in: .whitespaces),
                    unitPrice: draft.price ?? 0
                )
            }
        }
        store.updateBill(updated, roomID: roomID)
        isEditing = false
    }

    private func populateDraftsIfNeeded() {
        if items.isEmpty {
            items = Self.drafts(from: bill)
        }
    }

    /// Collapses per-unit items back into qty rows for editing. Safe only
    /// while the room is `.open` — no claims exist yet, so identical units
    /// are interchangeable.
    private static func drafts(from bill: Bill) -> [DraftItem] {
        var drafts: [DraftItem] = []
        for item in bill.items {
            if let index = drafts.firstIndex(where: {
                $0.name == item.name && $0.price == item.unitPrice
            }) {
                drafts[index].qty += 1
            } else {
                var draft = DraftItem()
                draft.name = item.name
                draft.price = item.unitPrice
                drafts.append(draft)
            }
        }
        return drafts.isEmpty ? [DraftItem()] : drafts
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
            let rooms = MockData.rooms()
            BillDetailCard(
                store: MockRoomStore(rooms: rooms),
                roomID: rooms[0].id,
                bill: rooms[0].bills.first ?? Bill(merchantName: "Alfamart bill"),
                canEdit: true
            )
            .padding(20)
        }
    }
}
