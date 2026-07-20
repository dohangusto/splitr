//
//  BillDetailCard.swift
//  splitr
//
//  Created by Christian Bryan Seputra on 18/07/26.
//

import SwiftUI

struct BillDetailItem: Identifiable, Equatable {
    let id = UUID()
    var name: String
    var quantity: Int
    var price: String
}

struct BillDetailCard: View {

    @State private var isEditing = false

    @State private var billTitle = "Alfamart bill"

    @State private var items: [BillDetailItem] = [
        BillDetailItem(
            name: "Cimory hazelnut",
            quantity: 1,
            price: "9,000"
        ),
        BillDetailItem(
            name: "Cimory hazelnut",
            quantity: 1,
            price: "9,000"
        ),
        BillDetailItem(
            name: "Cimory hazelnut",
            quantity: 1,
            price: "9,000"
        )
    ]

    @State private var tax = "8,000"
    @State private var service = "0"
    @State private var discount = "0"
    @State private var subtotal = "34,000"

    private var isFormValid: Bool {
        !items.isEmpty && items.allSatisfy { item in
            !item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !item.price.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            (Int(item.price.filter { "0"..."9" ~= $0 }) ?? 0) > 0 &&
            item.quantity > 0
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // MARK: - Bill Title

            if isEditing {
                TextField("Bill name", text: $billTitle)
                    .font(.title3)
                    .foregroundStyle(.primary)
                    .padding(.bottom, 20)
            } else {
                Text(billTitle)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 20)
            }


            // MARK: - Bill Items

            VStack(spacing: 0) {

                ForEach($items) { $item in

                    if isEditing {

                        EditableBillItemRow(
                            name: $item.name,
                            quantity: $item.quantity,
                            price: $item.price,
                            onDelete: {
                                withAnimation {
                                    items.removeAll { $0.id == item.id }
                                }
                            }
                        )

                    } else {

                        BillItemRow(
                            name: item.name,
                            quantity: item.quantity,
                            price: item.price
                        )
                    }

                    if item.id != items.last?.id {
                        Divider()
                            .padding(.vertical, 16)
                    }
                }
            }


            // MARK: - Add Item

            if isEditing {

                Button {
                    addItem()
                } label: {
                    HStack(spacing: 8) {

                        Image(systemName: "plus")

                        Text("Add item")
                    }
                    .font(.headline)
                    .foregroundStyle(.blue)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                }
                .buttonStyle(.plain)
                .padding(.top, 16)

                Divider()
                    .padding(.vertical, 20)
            } else {

                Divider()
                    .padding(.vertical, 16)
            }


            // MARK: - Bill Summary

            VStack(spacing: 24) {

                EditableSummaryRow(
                    title: "Pajak",
                    value: $tax,
                    isEditing: isEditing
                )

                EditableSummaryRow(
                    title: "Servis",
                    value: $service,
                    isEditing: isEditing
                )

                EditableSummaryRow(
                    title: "Diskon",
                    value: $discount,
                    isEditing: isEditing
                )

                EditableSummaryRow(
                    title: "Subtotal",
                    value: $subtotal,
                    isEditing: isEditing
                )
            }


            // MARK: - Edit / Done Button

            Button {

                withAnimation(.easeInOut(duration: 0.2)) {
                    isEditing.toggle()
                }

            } label: {

                HStack(spacing: 12) {

                    Image(
                        systemName:
                            isEditing
                            ? "checkmark"
                            : "pencil"
                    )
                    .font(.system(size: 20))

                    Text(
                        isEditing
                        ? "Done"
                        : "Edit details"
                    )
                    .font(.headline)
                    .foregroundStyle(isEditing && !isFormValid ? .secondary : .primary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(isEditing && !isFormValid ? Color(.systemGray6) : Color.white)
                .overlay {
                    RoundedRectangle(
                        cornerRadius: 28,
                        style: .continuous
                    )
                    .stroke(
                        isEditing && !isFormValid ? Color.clear : Color(.systemGray5),
                        lineWidth: 1
                    )
                }
            }
            .buttonStyle(.plain)
            .padding(.top, 24)
            .disabled(isEditing && !isFormValid)
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
        .onAppear {
            recalculateSummary()
        }
        .onChange(of: items) { _, _ in
            recalculateSummary()
        }
        .onChange(of: service) { _, _ in
            recalculateSummary()
        }
    }


    // MARK: - Add Item

    private func addItem() {

        let newItem = BillDetailItem(
            name: "",
            quantity: 1,
            price: ""
        )

        withAnimation {
            items.append(newItem)
        }
    }

    private func parsePrice(_ priceString: String) -> Int {
        let cleaned = priceString.filter { "0"..."9" ~= $0 }
        return Int(cleaned) ?? 0
    }

    private func formatRupiah(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private func recalculateSummary() {
        let subtotalInt = items.reduce(0) { total, item in
            total + (item.quantity * parsePrice(item.price))
        }
        let serviceInt = parsePrice(service)
        let taxInt = (subtotalInt + serviceInt) * 10 / 100

        subtotal = formatRupiah(subtotalInt)
        tax = formatRupiah(taxInt)
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


// MARK: - Editable Bill Item Row

private struct EditableBillItemRow: View {

    @Binding var name: String
    @Binding var quantity: Int
    @Binding var price: String
    let onDelete: () -> Void

    var body: some View {

        HStack(spacing: 12) {

            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.red)
                    .font(.title3)
            }
            .buttonStyle(.plain)

            // Item Name

            TextField(
                "Item name",
                text: $name
            )
            .font(.headline)


            Spacer()


            // Quantity

            HStack(spacing: 2) {

                Text("x")
                    .foregroundStyle(.secondary)

                TextField(
                    "1",
                    value: $quantity,
                    format: .number
                )
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .frame(width: 30)
            }


            Spacer()


            // Price

            TextField(
                "Price",
                text: $price
            )
            .font(.headline)
            .keyboardType(.numberPad)
            .multilineTextAlignment(.trailing)
            .frame(width: 80)
        }
    }
}


// MARK: - Bill Summary Row

private struct EditableSummaryRow: View {

    let title: String

    @Binding var value: String

    let isEditing: Bool

    var body: some View {

        HStack {

            Text(title)
                .font(.body)
                .foregroundStyle(.secondary)

            Spacer()

            if isEditing {

                TextField(
                    "0",
                    text: $value
                )
                .font(.headline)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 100)

            } else {

                Text(value)
                    .font(.headline)
                    .foregroundStyle(.primary)
            }
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

            BillDetailCard()
                .padding(20)
        }
    }
}
