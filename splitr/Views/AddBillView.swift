import SwiftUI
import SplitBillCore

/// Bill entry and the mandatory OCR review step. Manual entry starts blank;
/// the scan flow passes a `ParsedReceipt` whose drafts prefill the form —
/// OCR output never becomes a Bill without passing through here and the
/// user explicitly tapping Save.
struct AddBillView: View {
    let store: any RoomStoring
    let roomID: UUID
    /// Present when reviewing a scanned receipt; nil for manual entry.
    var scan: ParsedReceipt? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var merchant = ""
    @State private var taxPercent = 10
    @State private var servicePercent = 5
    @State private var taxBasis: TaxBasis = .subtotalPlusService
    @State private var items: [DraftItem] = [DraftItem()]

    private var validItems: [DraftItem] {
        items.filter {
            !$0.name.trimmingCharacters(in: .whitespaces).isEmpty && ($0.price ?? 0) > 0
        }
    }

    private var subtotal: Int {
        validItems.reduce(0) { $0 + ($1.price ?? 0) * $1.qty }
    }

    var body: some View {
        NavigationStack {
            Form {
                if scan != nil {
                    Section {
                        Label {
                            Text("Scanned — please verify. Check every name and price against the paper receipt before saving.")
                                .font(.subheadline)
                        } icon: {
                            Image(systemName: "doc.viewfinder")
                        }
                        .foregroundStyle(.orange)
                    }
                }

                Section("Merchant") {
                    TextField("Merchant name", text: $merchant)
                }

                Section("Line items") {
                    ForEach($items) { $item in
                        DraftItemRow(item: $item)
                    }
                    .onDelete { items.remove(atOffsets: $0) }
                    Button {
                        items.append(DraftItem())
                    } label: {
                        Label("Add Item", systemImage: "plus.circle")
                    }
                }

                Section("Tax & service") {
                    Stepper("PB1 tax: \(taxPercent)%", value: $taxPercent, in: 0...20)
                    Stepper("Service charge: \(servicePercent)%", value: $servicePercent, in: 0...15)
                    Picker("Tax applies to", selection: $taxBasis) {
                        Text("Subtotal + service").tag(TaxBasis.subtotalPlusService)
                        Text("Subtotal only").tag(TaxBasis.subtotal)
                    }
                }

                if let scan, !scan.unparsedLines.isEmpty {
                    Section {
                        ForEach(scan.unparsedLines, id: \.self) { line in
                            Text(line)
                                .font(.callout.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("Couldn't read these lines")
                    } footer: {
                        Text("Add them as items above if they belong on the bill.")
                    }
                }

                Section {
                    LabeledContent("Subtotal", value: subtotal.rupiah)
                } footer: {
                    Text("Each unit of a quantity becomes its own claimable row — friends claim per portion.")
                }
            }
            .navigationTitle(scan == nil ? "Add Bill" : "Review Scan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(merchant.trimmingCharacters(in: .whitespaces).isEmpty
                            || validItems.isEmpty)
                }
            }
            .onAppear {
                guard let scan else { return }
                merchant = scan.merchantName ?? ""
                taxPercent = scan.taxPercent ?? taxPercent
                servicePercent = scan.servicePercent ?? 0
                taxBasis = scan.taxBasis ?? taxBasis
                if !scan.items.isEmpty {
                    items = scan.items
                }
            }
        }
    }

    private func save() {
        // Qty explosion: one BillItem per unit, so each unit is claimable alone.
        let billItems = validItems.flatMap { draft in
            (0..<draft.qty).map { _ in
                BillItem(
                    name: draft.name.trimmingCharacters(in: .whitespaces),
                    unitPrice: draft.price ?? 0
                )
            }
        }
        let bill = Bill(
            merchantName: merchant.trimmingCharacters(in: .whitespaces),
            taxRate: .percent(taxPercent),
            serviceChargeRate: .percent(servicePercent),
            taxBasis: taxBasis,
            items: billItems
        )
        store.addBill(bill, roomID: roomID)
        dismiss()
    }
}

private struct DraftItemRow: View {
    @Binding var item: DraftItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField("Item name", text: $item.name)
                if item.needsReview {
                    Label("Check this row", systemImage: "exclamationmark.triangle.fill")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Low-confidence scan — check this row")
                }
            }
            HStack {
                TextField("Unit price (Rp)", value: $item.price, format: .number)
                    .keyboardType(.numberPad)
                Stepper("×\(item.qty)", value: $item.qty, in: 1...20)
                    .fixedSize()
            }
            .font(.subheadline)
        }
        .onChange(of: item.name) { item.needsReview = false }
        .onChange(of: item.price) { item.needsReview = false }
    }
}
