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

    var body: some View {
        NavigationStack {
            AddBillForm(store: store, roomID: roomID, scan: scan)
        }
    }
}

/// The bill form without its own `NavigationStack`, so the scan flow can
/// host it inside its stack — a sheet must keep one stable stack across
/// phase changes or in-flight picker dismissals tear the whole sheet down.
struct AddBillForm: View {
    let store: any RoomStoring
    let roomID: UUID
    var scan: ParsedReceipt? = nil
    /// Present when editing an already-saved bill (room still `.open`).
    var existingBill: Bill? = nil
    /// The captured receipt image, passed in-memory by the scan flow.
    var photo: UIImage? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var merchant = ""
    @State private var taxPercent = 10
    @State private var servicePercent = 5
    @State private var taxBasis: TaxBasis = .subtotalPlusService
    @State private var items: [DraftItem] = [DraftItem()]
    @State private var displayedPhoto: UIImage?

    private var validItems: [DraftItem] {
        items.filter {
            !$0.name.trimmingCharacters(in: .whitespaces).isEmpty && ($0.price ?? 0) > 0
        }
    }

    private var subtotal: Int {
        validItems.reduce(0) { $0 + ($1.price ?? 0) * $1.qty }
    }

    private var isReadOnly: Bool {
        let state = store.room(withID: roomID)?.state
        return state != .open && state != .claiming
    }

    var body: some View {
        VStack(spacing: 0) {
            // The photo stays pinned above the form the whole time, so
            // correcting OCR mistakes never means leaving the edit screen.
            if let displayedPhoto {
                ReceiptPhotoPane(image: displayedPhoto)
            }
            billForm
        }
    }

    private var billForm: some View {
        Form {
            if scan != nil {
                Section {
                    Label {
                        Text("Check items against the receipt before saving.")
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

            Section {
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
                .onDelete { items.remove(atOffsets: $0) }
                Button {
                    items.append(DraftItem())
                } label: {
                    Label("Add Item", systemImage: "plus.circle")
                }
            } header: {
                Text("Line items")
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
            }
        }
        .disabled(isReadOnly)
        .navigationTitle(existingBill != nil ? (isReadOnly ? "View Bill" : "Edit Bill") : scan == nil ? "Add Bill" : "Review Scan")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                if isReadOnly {
                    Button("Done") { dismiss() }
                } else {
                    Button("Cancel") { dismiss() }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                if !isReadOnly {
                    Button("Save") { save() }
                        .disabled(merchant.trimmingCharacters(in: .whitespaces).isEmpty
                            || validItems.isEmpty)
                }
            }
        }
        .onAppear {
            displayedPhoto = photo ?? ReceiptPhotoStore.load(existingBill?.photoReference)
            if let existingBill {
                merchant = existingBill.merchantName
                taxPercent = existingBill.taxRate.basisPoints / 100
                servicePercent = existingBill.serviceChargeRate.basisPoints / 100
                taxBasis = existingBill.taxBasis
                items = Self.drafts(from: existingBill)
            } else if let scan {
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
        if var updated = existingBill {
            // Editing (room still .open): keep id, createdAt, and the
            // stored photo; replace everything the form controls.
            updated.merchantName = merchant.trimmingCharacters(in: .whitespaces)
            updated.taxRate = .percent(taxPercent)
            updated.serviceChargeRate = .percent(servicePercent)
            updated.taxBasis = taxBasis
            updated.items = billItems
            store.updateBill(updated, roomID: roomID)
        } else {
            var photoReference: String?
            if let photo { photoReference = ReceiptPhotoStore.save(photo) }
            let bill = Bill(
                merchantName: merchant.trimmingCharacters(in: .whitespaces),
                photoReference: photoReference,
                taxRate: .percent(taxPercent),
                serviceChargeRate: .percent(servicePercent),
                taxBasis: taxBasis,
                items: billItems
            )
            store.addBill(bill, roomID: roomID)
        }
        dismiss()
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
