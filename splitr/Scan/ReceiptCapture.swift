@preconcurrency import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import SplitBillCore
import SwiftUI
import Vision

// MARK: - Capture model

/// Drives the capture screen: camera lifecycle, live document detection,
/// and the shutter gate. The screen answers one question — "is this
/// receipt fully in frame and readable?" — and the gate *is* the answer:
/// the shutter arms only while a document quad has been detected
/// continuously for ~half a second and covers enough of the frame.
@Observable
@MainActor
final class ReceiptCaptureModel {

    enum Status {
        case checkingPermission
        /// Camera permission denied — actionable copy + Settings route.
        case denied
        /// No usable camera (e.g. simulator) — photo import still works.
        case unavailable
        case running
    }

    private(set) var status: Status = .checkingPermission
    /// Latest detected document quad, normalized capture-device points
    /// (sensor space, top-left origin) — the preview view converts these
    /// to layer coordinates for the overlay.
    private(set) var quadDevicePoints: [CGPoint]?
    /// True while the quad has been stable long enough to trust the shot.
    private(set) var isArmed = false
    private(set) var isTorchOn = false
    private(set) var isCapturing = false

    let controller = CameraController()

    // Shutter gate tuning. Forgiving on purpose: a shutter that refuses to
    // arm on a good receipt is worse than one that lets a mediocre photo
    // through (the edit screen catches those).
    private static let armAfter: TimeInterval = 0.5
    private static let dropoutTolerance: TimeInterval = 0.4
    private static let minimumFrameCoverage: CGFloat = 0.12

    private var firstGoodQuadAt: Date?
    private var lastGoodQuadAt: Date?

    func start() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else {
                status = .denied
                return
            }
        default:
            status = .denied
            return
        }
        let configured = await controller.configure { [weak self] quad in
            guard let self else { return }
            Task { @MainActor in self.handle(quad: quad) }
        }
        status = configured ? .running : .unavailable
        if configured { controller.startRunning() }
    }

    func stop() {
        controller.stopRunning()
    }

    func toggleTorch() {
        isTorchOn.toggle()
        controller.setTorch(on: isTorchOn)
    }

    func capturePhoto() async -> UIImage? {
        guard !isCapturing else { return nil }
        isCapturing = true
        defer { isCapturing = false }
        return await controller.capturePhoto()
    }

    private func handle(quad: DetectedDocumentObservation?) {
        let now = Date()
        if let quad, quad.boundingBox.width * quad.boundingBox.height >= Self.minimumFrameCoverage {
            // Vision points are lower-left origin; device points are
            // top-left origin in the same (sensor) space.
            quadDevicePoints = [quad.topLeft, quad.topRight, quad.bottomRight, quad.bottomLeft]
                .map { CGPoint(x: $0.x, y: 1 - $0.y) }
            if firstGoodQuadAt == nil { firstGoodQuadAt = now }
            lastGoodQuadAt = now
        } else {
            quadDevicePoints = nil
            if let last = lastGoodQuadAt, now.timeIntervalSince(last) > Self.dropoutTolerance {
                firstGoodQuadAt = nil
                lastGoodQuadAt = nil
            }
        }
        isArmed = firstGoodQuadAt.map { now.timeIntervalSince($0) >= Self.armAfter } ?? false
            && lastGoodQuadAt.map { now.timeIntervalSince($0) <= Self.dropoutTolerance } ?? false
    }
}

// MARK: - Camera controller

/// Owns the `AVCaptureSession` and its queue. Back wide camera (not
/// ultrawide), near-focus for 15–25 cm receipt shots, maximum photo
/// dimensions the format supports, torch strictly manual — flash blows
/// out glossy thermal paper.
// `nonisolated`: the project defaults types to MainActor, but this class
// confines all its state to its own session queue.
nonisolated final class CameraController: NSObject, @unchecked Sendable {

    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "splitr.receipt-capture")
    private var device: AVCaptureDevice?
    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private var onQuad: (@Sendable (DetectedDocumentObservation?) -> Void)?

    // Segmentation throttle: a few frames per second is plenty.
    private var lastAnalysis = Date.distantPast
    private var isAnalyzing = false
    private static let analysisInterval: TimeInterval = 0.25

    private var photoContinuation: CheckedContinuation<UIImage?, Never>?

    /// Returns false when no usable camera exists (simulator).
    func configure(onQuad: @escaping @Sendable (DetectedDocumentObservation?) -> Void) async -> Bool {
        self.onQuad = onQuad
        return await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self.configureOnQueue())
            }
        }
    }

    private func configureOnQueue() -> Bool {
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: camera) else {
            return false
        }
        device = camera
        session.beginConfiguration()
        session.sessionPreset = .photo
        guard session.canAddInput(input), session.canAddOutput(photoOutput) else {
            session.commitConfiguration()
            return false
        }
        session.addInput(input)
        session.addOutput(photoOutput)
        // Every pixel matters for receipt type: ask for the largest photo
        // the active format supports, not a default preset.
        if let best = camera.activeFormat.supportedMaxPhotoDimensions
            .max(by: { Int($0.width) * Int($0.height) < Int($1.width) * Int($1.height) }) {
            photoOutput.maxPhotoDimensions = best
        }
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        }
        session.commitConfiguration()

        if (try? camera.lockForConfiguration()) != nil {
            // Receipts are shot close; bias autofocus to the near range.
            if camera.isAutoFocusRangeRestrictionSupported {
                camera.autoFocusRangeRestriction = .near
            }
            if camera.isFocusModeSupported(.continuousAutoFocus) {
                camera.focusMode = .continuousAutoFocus
            }
            camera.unlockForConfiguration()
        }
        return true
    }

    func startRunning() {
        queue.async {
            if !self.session.isRunning { self.session.startRunning() }
        }
    }

    func stopRunning() {
        queue.async {
            if self.session.isRunning { self.session.stopRunning() }
            self.setTorchOnQueue(on: false)
        }
    }

    func setTorch(on: Bool) {
        queue.async { self.setTorchOnQueue(on: on) }
    }

    private func setTorchOnQueue(on: Bool) {
        guard let device, device.hasTorch,
              (try? device.lockForConfiguration()) != nil else { return }
        device.torchMode = on ? .on : .off
        device.unlockForConfiguration()
    }

    func capturePhoto() async -> UIImage? {
        await withCheckedContinuation { continuation in
            queue.async {
                guard self.photoContinuation == nil, self.session.isRunning else {
                    continuation.resume(returning: nil)
                    return
                }
                self.photoContinuation = continuation
                let settings = AVCapturePhotoSettings()
                settings.maxPhotoDimensions = self.photoOutput.maxPhotoDimensions
                settings.flashMode = .off // never auto-flash on thermal paper
                self.photoOutput.capturePhoto(with: settings, delegate: self)
            }
        }
    }
}

nonisolated extension CameraController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        let now = Date()
        guard !isAnalyzing, now.timeIntervalSince(lastAnalysis) >= Self.analysisInterval,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        isAnalyzing = true
        lastAnalysis = now
        let onQuad = onQuad
        Task.detached(priority: .utility) { [weak self] in
            let quad = try? await DetectDocumentSegmentationRequest().perform(on: pixelBuffer)
            onQuad?(quad ?? nil)
            self?.queue.async { self?.isAnalyzing = false }
        }
    }
}

nonisolated extension CameraController: AVCapturePhotoCaptureDelegate {
    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: (any Error)?
    ) {
        let image: UIImage? = {
            guard error == nil, let data = photo.fileDataRepresentation() else { return nil }
            return UIImage(data: data)
        }()
        queue.async {
            self.photoContinuation?.resume(returning: image)
            self.photoContinuation = nil
        }
    }
}

// MARK: - Still-image pipeline

/// Camera-independent scan pipeline: any `CGImage` in — camera shot,
/// photo-library import, or bundled fixture — corrected image + OCR out.
/// This is what makes parsing testable and the screen runnable in the
/// simulator.
enum ReceiptScanPipeline {

    /// Perspective-corrects the receipt using its detected quad (receipts
    /// are always curled and held at an angle — correction happens *before*
    /// OCR), then recognizes. When no document is detected the original
    /// image is used as-is; zero recognized items is a normal outcome.
    static func scan(
        _ image: UIImage,
        recognizer: any ReceiptRecognizing
    ) async throws -> (parsed: ParsedReceipt, corrected: UIImage) {
        let upright = image.normalizedUp()
        let corrected = await perspectiveCorrected(upright) ?? upright
        guard let cgImage = corrected.cgImage else {
            return (ParsedReceipt(), corrected)
        }
        let recognized = try await recognizer.recognize(cgImage)
        return (ReceiptParser.parse(recognized), corrected)
    }

    private static func perspectiveCorrected(_ image: UIImage) async -> UIImage? {
        guard let cgImage = image.cgImage,
              let quad = try? await DetectDocumentSegmentationRequest().perform(on: cgImage),
              // A quad covering a sliver of the frame is a misdetection;
              // cropping to it would destroy the receipt. Better to OCR
              // the uncorrected photo than a corrected patch of nothing.
              quad.boundingBox.width * quad.boundingBox.height >= 0.2
        else { return nil }

        let ciImage = CIImage(cgImage: cgImage)
        let size = ciImage.extent.size
        // Vision's lower-left-origin normalized points match CIImage
        // coordinates directly.
        let point = { (p: NormalizedPoint) in
            CGPoint(x: p.x * size.width, y: p.y * size.height)
        }
        let filter = CIFilter.perspectiveCorrection()
        filter.inputImage = ciImage
        filter.topLeft = point(quad.topLeft)
        filter.topRight = point(quad.topRight)
        filter.bottomRight = point(quad.bottomRight)
        filter.bottomLeft = point(quad.bottomLeft)
        guard let output = filter.outputImage else { return nil }
        let context = CIContext()
        guard let correctedCG = context.createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: correctedCG)
    }
}

private extension UIImage {
    /// Redraws with `.up` orientation so Vision and Core Image see the
    /// pixels the way the user did.
    func normalizedUp() -> UIImage {
        guard imageOrientation != .up else { return self }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

// MARK: - Capture view

/// Host-only capture screen. One primary action: the shutter. The quad
/// overlay and the shutter's armed state are the only feedback — if the
/// framing is wrong, the shutter refuses to arm.
struct ReceiptCaptureView: View {
    @State private var model = ReceiptCaptureModel()
    /// Called with the raw capture; the flow runs the scan pipeline.
    var onCapture: (UIImage) -> Void
    /// Secondary path: import an existing photo instead.
    var onPickPhoto: () -> Void
    var onCancel: () -> Void

    var body: some View {
        ZStack {
            switch model.status {
            case .checkingPermission:
                Color.black.ignoresSafeArea()
            case .running:
                cameraSurface
            case .denied:
                permissionDenied
            case .unavailable:
                cameraUnavailable
            }
        }
        .navigationTitle("Scan Receipt")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: onCancel)
            }
            // Rare case, possible but not on the main surface.
            ToolbarItem(placement: .secondaryAction) {
                Button("Choose a Photo", systemImage: "photo.on.rectangle", action: onPickPhoto)
            }
        }
        .task { await model.start() }
        .onDisappear { model.stop() }
    }

    private var cameraSurface: some View {
        CameraPreview(controller: model.controller, quadDevicePoints: model.quadDevicePoints)
            .ignoresSafeArea()
            .overlay(alignment: .bottom) { shutterBar }
            .overlay(alignment: .topTrailing) { torchButton }
            .background(Color.black.ignoresSafeArea())
    }

    private var shutterBar: some View {
        Button {
            Task {
                guard let image = await model.capturePhoto() else { return }
                onCapture(image)
            }
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(.white, lineWidth: 4)
                    .frame(width: 72, height: 72)
                Circle()
                    .fill(model.isArmed ? .white : .white.opacity(0.3))
                    .frame(width: 58, height: 58)
            }
        }
        .disabled(!model.isArmed || model.isCapturing)
        .animation(.easeInOut(duration: 0.15), value: model.isArmed)
        .padding(.bottom, 24)
        .accessibilityLabel(model.isArmed ? "Take photo" : "Shutter disabled — receipt not in frame")
    }

    private var torchButton: some View {
        Button {
            model.toggleTorch()
        } label: {
            Image(systemName: model.isTorchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                .font(.title3)
                .foregroundStyle(model.isTorchOn ? .yellow : .white)
                .padding(12)
                .background(.black.opacity(0.4), in: Circle())
        }
        .padding()
        .accessibilityLabel(model.isTorchOn ? "Turn torch off" : "Turn torch on")
    }

    private var permissionDenied: some View {
        ContentUnavailableView {
            Label("Camera access is off", systemImage: "camera.fill")
        } description: {
            Text("splitr needs the camera to scan receipts. Turn it on in Settings, or choose an existing photo instead.")
        } actions: {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
            Button("Choose a Photo", action: onPickPhoto)
        }
    }

    private var cameraUnavailable: some View {
        ContentUnavailableView {
            Label("No camera here", systemImage: "camera")
        } description: {
            Text("This device has no usable camera — choose a receipt photo instead.")
        } actions: {
            Button("Choose a Photo", action: onPickPhoto)
                .buttonStyle(.borderedProminent)
        }
    }
}

// MARK: - Preview layer + quad overlay

private struct CameraPreview: UIViewRepresentable {
    let controller: CameraController
    let quadDevicePoints: [CGPoint]?

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = controller.session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {
        view.show(quadDevicePoints: quadDevicePoints)
    }

    final class PreviewView: UIView {
        override static var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

        private let quadLayer: CAShapeLayer = {
            let shape = CAShapeLayer()
            shape.fillColor = UIColor.systemYellow.withAlphaComponent(0.15).cgColor
            shape.strokeColor = UIColor.systemYellow.cgColor
            shape.lineWidth = 2
            shape.lineJoin = .round
            return shape
        }()

        override init(frame: CGRect) {
            super.init(frame: frame)
            layer.addSublayer(quadLayer)
        }

        required init?(coder: NSCoder) { fatalError("unused") }

        func show(quadDevicePoints: [CGPoint]?) {
            guard let points = quadDevicePoints, points.count == 4 else {
                quadLayer.path = nil
                return
            }
            let converted = points.map {
                previewLayer.layerPointConverted(fromCaptureDevicePoint: $0)
            }
            let path = UIBezierPath()
            path.move(to: converted[0])
            for point in converted.dropFirst() { path.addLine(to: point) }
            path.close()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            quadLayer.path = path.cgPath
            CATransaction.commit()
        }
    }
}
