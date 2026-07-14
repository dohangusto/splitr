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
    @State private var photoSelection: PhotosPickerItem?

    enum Phase {
        case pickSource
        case processing
        case review(ParsedReceipt)
        case failed(String)
    }

    var body: some View {
        switch phase {
        case .pickSource:
            sourcePicker
        case .processing:
            NavigationStack {
                ProgressView("Reading receipt…")
                    .navigationTitle("Scan Receipt")
                    .navigationBarTitleDisplayMode(.inline)
            }
        case .review(let parsed):
            // The non-negotiable step: parsed drafts go through the edit
            // form and only an explicit Save creates the Bill.
            AddBillView(store: store, roomID: roomID, scan: parsed)
        case .failed(let message):
            NavigationStack {
                ContentUnavailableView {
                    Label("Couldn't read that", systemImage: "doc.viewfinder")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try Again") { phase = .pickSource }
                        .buttonStyle(.borderedProminent)
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
        }
    }

    private var sourcePicker: some View {
        NavigationStack {
            List {
                Section {
                    if DocumentCameraView.isSupported {
                        Button {
                            showCamera = true
                        } label: {
                            Label("Scan with Camera", systemImage: "doc.viewfinder")
                        }
                    }
                    PhotosPicker(selection: $photoSelection, matching: .images) {
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
            .fullScreenCover(isPresented: $showCamera) {
                DocumentCameraView { images in
                    process(images)
                } onCancel: {
                    showCamera = false
                }
                .ignoresSafeArea()
            }
            .onChange(of: photoSelection) { _, item in
                guard let item else { return }
                phase = .processing
                Task {
                    guard let data = try? await item.loadTransferable(type: Data.self),
                          let cgImage = UIImage(data: data)?.cgImage else {
                        phase = .failed("That photo couldn't be loaded. Try another one.")
                        return
                    }
                    await recognize([cgImage])
                }
            }
        }
    }

    private func process(_ images: [UIImage]) {
        showCamera = false
        phase = .processing
        let cgImages = images.compactMap(\.cgImage)
        Task { await recognize(cgImages) }
    }

    private func recognize(_ images: [CGImage]) async {
        do {
            var lines: [String] = []
            for image in images {
                lines += try await recognizer.recognizeLines(in: image)
            }
            let parsed = ReceiptParser.parse(lines: lines)
            if parsed.items.isEmpty && parsed.unparsedLines.isEmpty {
                phase = .failed("No text found. Get closer to the receipt in good light, or enter the bill manually.")
            } else {
                phase = .review(parsed)
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
