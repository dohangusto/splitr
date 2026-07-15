import PhotosUI
import SwiftUI
import VisionKit

/// Receipt scanning flow: capture (document camera or photo library) →
/// OCR → parse → the mandatory review form. OCR output never becomes a
/// Bill directly; the only path out of here is through `AddBillView`,
/// where the user verifies and explicitly confirms.
struct ReceiptScanFlow: View {
    let store: any RoomStoring
    let roomID: UUID
    var recognizer: any ReceiptTextRecognizing = VisionReceiptRecognizer()

    @Environment(\.dismiss) private var dismiss
    @State private var phase: Phase = .pickSource
    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var photoSelection: PhotosPickerItem?
    @State private var capturedImages: [UIImage] = []

    enum Phase {
        case pickSource
        case processing
        case review(ParsedReceipt, photo: UIImage?)
        case failed(String)
    }

    // One NavigationStack stays mounted for every phase, and the camera
    // cover / photo picker hang off it — never off a view inside the
    // `switch`. If their anchor view is swapped out while the picker is
    // still dismissing, SwiftUI propagates that dismissal to the parent
    // presentation and the whole sheet closes (review flashed then died).
    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .pickSource:
                    sourcePicker
                case .processing:
                    ProgressView("Reading receipt…")
                        .navigationTitle("Scan Receipt")
                        .navigationBarTitleDisplayMode(.inline)
                case .review(let parsed, let photo):
                    // The non-negotiable step: parsed drafts go through the
                    // edit form and only an explicit Save creates the Bill.
                    // The photo rides along so the user verifies against it
                    // without leaving the form.
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
                            Button("Try Again") {
                                phase = .pickSource
                            }
                        }
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showCamera, onDismiss: processCapturedImages) {
            DocumentCameraView { images in
                capturedImages = images
                showCamera = false
            } onCancel: {
                showCamera = false
            }
            .ignoresSafeArea()
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoSelection, matching: .images)
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
                await recognize([image])
            }
        }
    }

    private var sourcePicker: some View {
        List {
            Section {
                if DocumentCameraView.isSupported {
                    Button {
                        showCamera = true
                    } label: {
                        Label("Scan with Camera", systemImage: "doc.viewfinder")
                    }
                }
                Button {
                    showPhotoPicker = true
                } label: {
                    Label("Choose a Photo", systemImage: "photo.on.rectangle")
                }
            } footer: {
                if DocumentCameraView.isSupported {
                    Text("The camera scanner crops and straightens the receipt automatically.")
                } else {
                    Text("The camera scanner needs a physical device — pick a receipt photo instead.")
                }
            }
        }
        .navigationTitle("Scan Receipt")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }

    /// Runs after the camera cover has fully dismissed, so the phase swap
    /// never races the cover's dismissal animation.
    private func processCapturedImages() {
        guard !capturedImages.isEmpty else { return }
        let images = capturedImages
        capturedImages = []
        phase = .processing
        Task { await recognize(images) }
    }

    private func recognize(_ images: [UIImage]) async {
        do {
            var lines: [String] = []
            for image in images {
                guard let cgImage = image.cgImage else { continue }
                lines += try await recognizer.recognizeLines(in: cgImage)
            }
            let parsed = ReceiptParser.parse(lines: lines)
            if parsed.items.isEmpty && parsed.unparsedLines.isEmpty {
                phase = .failed("No text found. Get closer to the receipt in good light, or enter the bill manually.")
            } else {
                phase = .review(parsed, photo: images.first)
            }
        } catch {
            phase = .failed("Text recognition failed. Try again, or enter the bill manually.")
        }
    }
}

/// VisionKit document camera (edge detection + perspective correction for
/// free). Requires a physical device; check `isSupported`.
struct DocumentCameraView: UIViewControllerRepresentable {
    var onFinish: ([UIImage]) -> Void
    var onCancel: () -> Void

    static var isSupported: Bool {
        VNDocumentCameraViewController.isSupported
    }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish, onCancel: onCancel)
    }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onFinish: ([UIImage]) -> Void
        let onCancel: () -> Void

        init(onFinish: @escaping ([UIImage]) -> Void, onCancel: @escaping () -> Void) {
            self.onFinish = onFinish
            self.onCancel = onCancel
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            onFinish((0..<scan.pageCount).map(scan.imageOfPage(at:)))
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            onCancel()
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFailWithError error: Error
        ) {
            onCancel()
        }
    }
}
