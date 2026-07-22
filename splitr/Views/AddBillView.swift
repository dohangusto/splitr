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
    /// Charges and discount are whole-rupiah amounts straight off the receipt.
    @State private var taxAmount = 0
    @State private var serviceAmount = 0
    @State private var discountAmount = 0
    @State private var items: [DraftItem] = [DraftItem()]
    @State private var displayedPhoto: UIImage?

    private var grandTotal: Int {
        subtotal + taxAmount + serviceAmount - discountAmount
    }

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
            // The real "OCR is never trusted blindly" gate: a single quiet
            // line reconciling the parsed items against the receipt's own
            // printed subtotal. Match → trust at a glance. Mismatch → hunt
            // the difference. No per-row confidence flags — a "low
            // confidence" mark doesn't change what the host does (they
            // reconcile either way), and OCR is confidently wrong as often
            // as it's hesitantly right.
            if let printed = scan?.printedSubtotal {
                Section {
                    reconciliationLine(printed: printed, summed: subtotal)
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

            Section("Charges & discount") {
                amountRow("PB1 tax", value: $taxAmount)
                amountRow("Service charge", value: $serviceAmount)
                amountRow("Discount", value: $discountAmount)
            }

            Section {
                LabeledContent("Subtotal", value: subtotal.rupiah)
                LabeledContent("Total") { Text(grandTotal.rupiah).bold() }
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
                taxAmount = existingBill.tax
                serviceAmount = existingBill.serviceCharge
                discountAmount = existingBill.discount
                items = Self.drafts(from: existingBill)
            } else if let scan {
                merchant = scan.merchantName ?? ""
                taxAmount = scan.taxAmount ?? 0
                serviceAmount = scan.serviceAmount ?? 0
                discountAmount = scan.discountAmount ?? 0
                if !scan.items.isEmpty {
                    items = scan.items
                }
            }
        }
    }

    /// One quiet line: parsed items vs. the receipt's printed subtotal,
    /// reflecting the host's live edits so it closes as they fix a row.
    @ViewBuilder
    private func reconciliationLine(printed: Int, summed: Int) -> some View {
        let diff = printed - summed
        if diff == 0 {
            Label {
                Text("Items match the receipt subtotal (\(printed.rupiah)).")
                    .font(.subheadline)
            } icon: {
                Image(systemName: "checkmark.circle")
            }
            .foregroundStyle(.secondary)
        } else {
            Label {
                Text(diff > 0
                    ? "Items are \(abs(diff).rupiah) under the receipt subtotal (\(printed.rupiah)) — check for a missing item."
                    : "Items are \(abs(diff).rupiah) over the receipt subtotal (\(printed.rupiah)) — check for a double-counted item.")
                    .font(.subheadline)
            } icon: {
                Image(systemName: "exclamationmark.circle")
            }
        }
    }

    /// A right-aligned whole-rupiah entry row for a charge or discount.
    private func amountRow(_ title: String, value: Binding<Int>) -> some View {
        LabeledContent(title) {
            TextField("0", value: value, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
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
            updated.tax = taxAmount
            updated.serviceCharge = serviceAmount
            updated.discount = discountAmount
            updated.items = billItems
            store.updateBill(updated, roomID: roomID)
        } else {
            var photoReference: String?
            if let photo { photoReference = ReceiptPhotoStore.save(photo) }
            let bill = Bill(
                merchantName: merchant.trimmingCharacters(in: .whitespaces),
                photoReference: photoReference,
                tax: taxAmount,
                serviceCharge: serviceAmount,
                discount: discountAmount,
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

struct DraftItemRow: View {
    @Binding var item: DraftItem

    // One line, name + price both editable inline — no confidence badge, no
    // "needs review" second line. (`needsReview`/`confidence` are still
    // captured in the draft; they're simply not shown.) The qty stepper
    // stays for manual entry, where "3× Es Teh" is a real case.
    var body: some View {
        HStack(spacing: 8) {
            TextField("Item name", text: $item.name)
            Stepper("×\(item.qty)", value: $item.qty, in: 1...20)
                .fixedSize()
            TextField("Price", value: $item.price, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 76)
        }
    }
}
