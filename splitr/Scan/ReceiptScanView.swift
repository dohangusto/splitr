import PhotosUI
import SplitBillCore
import SwiftUI

/// Receipt scanning flow: capture (custom camera, or photo library as the
/// secondary path) → perspective correction → OCR → parse → the mandatory
/// review form. OCR output never becomes a Bill directly; the only path
/// out of here is through `AddBillForm`, where the user verifies and
/// explicitly confirms. One receipt per pass — a room holds several bills
/// by entering this flow once per receipt, and a draft that fails is
/// discarded, never left looking real.
struct ReceiptScanFlow: View {
    let store: any RoomStoring
    let roomID: UUID
    let recognizer: any ReceiptRecognizing
    /// Where the flow starts: the custom camera, or straight into the system
    /// photo picker. Both feed the identical `ReceiptScanPipeline` — the
    /// picked image is perspective-corrected and orientation-normalized the
    /// same way a camera shot is; neither skips pre-OCR normalization.
    let source: Source

    init(
        store: any RoomStoring,
        roomID: UUID,
        recognizer: any ReceiptRecognizing = VisionReceiptRecognizer(),
        source: Source = .camera
    ) {
        self.store = store
        self.roomID = roomID
        self.recognizer = recognizer
        self.source = source
        _phase = State(initialValue: source == .camera ? .capture : .picking)
    }

    @Environment(\.dismiss) private var dismiss
    @State private var phase: Phase
    @State private var showPhotoPicker = false
    @State private var photoSelection: PhotosPickerItem?

    enum Source {
        case camera
        case photoLibrary
    }

    enum Phase {
        case capture
        /// Photo-library start: present the system picker without ever
        /// mounting the camera (so the camera-permission prompt never fires).
        case picking
        case processing
        case review(ParsedReceipt, photo: UIImage?)
        case failed(String)
    }

    // One NavigationStack stays mounted for every phase, and the photo
    // picker hangs off it — never off a view inside the `switch`. If its
    // anchor view is swapped out while the picker is still dismissing,
    // SwiftUI propagates that dismissal to the parent presentation and the
    // whole sheet closes (review flashed then died).
    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .capture:
                    ReceiptCaptureView { image in
                        process(image)
                    } onPickPhoto: {
                        showPhotoPicker = true
                    } onCancel: {
                        dismiss()
                    }
                case .picking:
                    // Neutral placeholder behind the picker — no camera. If
                    // the host cancels the picker, this is where they land.
                    ContentUnavailableView {
                        Label("Choose a receipt photo", systemImage: "photo.on.rectangle")
                    } description: {
                        Text("Pick a photo of the receipt to scan.")
                    } actions: {
                        Button("Choose Photo") { showPhotoPicker = true }
                            .buttonStyle(.borderedProminent)
                    }
                    .navigationTitle("Select Photo")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { dismiss() }
                        }
                    }
                case .processing:
                    ProgressView("Reading receipt…")
                        .navigationTitle("Scan Receipt")
                        .navigationBarTitleDisplayMode(.inline)
                case .review(let parsed, let photo):
                    // The non-negotiable step: parsed drafts go through the
                    // edit form and only an explicit Save creates the Bill.
                    // Zero recognized items is a normal outcome — the form
                    // opens empty and the host types the items in. The photo
                    // rides along so the user verifies against it without
                    // leaving the form.
                    AddBillForm(store: store, roomID: roomID, scan: parsed, photo: photo)
                case .failed(let message):
                    ContentUnavailableView {
                        Label("Couldn't read that", systemImage: "doc.viewfinder")
                    } description: {
                        Text(message)
                    }
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { dismiss() }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Try Again") { phase = .capture }
                        }
                    }
                }
            }
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoSelection, matching: .images)
        .task {
            // Photo-library start: open the picker immediately.
            if case .picking = phase { showPhotoPicker = true }
        }
        .onChange(of: photoSelection) { _, item in
            guard let item else { return }
            photoSelection = nil
            phase = .processing
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else {
                    phase = .failed("That photo couldn't be loaded. Try another one.")
                    return
                }
                await scan(image)
            }
        }
    }

    private func process(_ image: UIImage) {
        phase = .processing
        Task { await scan(image) }
    }

    private func scan(_ image: UIImage) async {
        do {
            let result = try await ReceiptScanPipeline.scan(image, recognizer: recognizer)
            saveDirectly(result.parsed, photo: result.corrected)
        } catch {
            // The draft dies here — retry or cancel, never a phantom.
            phase = .failed("Text recognition failed. Try again, or enter the bill manually.")
        }
    }

    private func saveDirectly(_ parsed: ParsedReceipt, photo: UIImage?) {
        let validItems = parsed.items.filter {
            !$0.name.trimmingCharacters(in: .whitespaces).isEmpty && ($0.price ?? 0) > 0
        }
        
        let billItems = validItems.flatMap { draft in
            (0..<draft.qty).map { _ in
                BillItem(
                    name: draft.name.trimmingCharacters(in: .whitespaces),
                    unitPrice: draft.price ?? 0
                )
            }
        }
        
        var photoReference: String?
        if let photo { photoReference = ReceiptPhotoStore.save(photo) }
        
        let rawMerchantName = parsed.merchantName?.trimmingCharacters(in: .whitespaces) ?? ""
        let merchant = rawMerchantName.isEmpty ? "Receipt" : rawMerchantName
        
        let bill = Bill(
            merchantName: merchant,
            photoReference: photoReference,
            tax: parsed.taxAmount ?? 0,
            serviceCharge: parsed.serviceAmount ?? 0,
            discount: parsed.discountAmount ?? 0,
            items: billItems
        )
        store.addBill(bill, roomID: roomID)
        dismiss()
    }
}
