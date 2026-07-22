import CoreGraphics
import Foundation
import SplitBillCore
import Vision

/// Text recognition behind a protocol so parsing flows are testable and
/// runnable from any image source — camera capture, photo library, or a
/// fixture image. Nothing here touches AVFoundation.
protocol ReceiptRecognizing: Sendable {
    /// Recognizes the receipt's content — free lines plus any detected
    /// table structure — with per-line geometry and confidence preserved.
    func recognize(_ image: CGImage) async throws -> RecognizedReceipt
}

/// Vision-backed implementation using the iOS 26 `RecognizeDocumentsRequest`,
/// which returns document structure (tables of rows and cells) instead of
/// loose text — receipt line items are a table (name | qty | price), and
/// reading Vision's table beats reconstructing columns from x positions.
struct VisionReceiptRecognizer: ReceiptRecognizing {

    func recognize(_ image: CGImage) async throws -> RecognizedReceipt {
        let requestHandler = VNImageRequestHandler(cgImage: image, options: [:])
        let request = VNRecognizeTextRequest()
        request.recognitionLanguages = ["id-ID", "en-US"]
        request.usesLanguageCorrection = false
        request.recognitionLevel = .accurate
        
        try await Task.detached {
            try requestHandler.perform([request])
        }.value
        
        guard let observations = request.results else {
            return RecognizedReceipt(rows: [])
        }
        
        var fragments: [SplitBillCore.RecognizedText] = []
        for observation in observations {
            guard let candidate = observation.topCandidates(1).first else { continue }
            let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            
            // Convert bounding box from Vision's bottom-left origin to top-left origin:
            let boundingBox = observation.boundingBox
            let box = SplitBillCore.NormalizedRect(
                x: Double(boundingBox.origin.x),
                y: Double(1 - boundingBox.origin.y - boundingBox.size.height),
                width: Double(boundingBox.size.width),
                height: Double(boundingBox.size.height)
            )
            
            fragments.append(SplitBillCore.RecognizedText(
                text: text,
                box: box,
                confidence: Double(observation.confidence)
            ))
        }
        
        let lines = RecognizedReceipt.assembleLines(fragments)
        return RecognizedReceipt(rows: lines.map { SplitBillCore.ReceiptRow.line($0) })
    }
}
