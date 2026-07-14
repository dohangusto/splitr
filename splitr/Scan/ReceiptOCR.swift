import CoreGraphics
import Foundation
import Vision

/// Text recognition behind a protocol so parsing flows are testable
/// without a camera or Vision.
protocol ReceiptTextRecognizing: Sendable {
    /// Recognizes text in a receipt photo and returns visual lines,
    /// top to bottom, left to right.
    func recognizeLines(in image: CGImage) async throws -> [String]
}

/// Vision-backed implementation using the Swift `RecognizeTextRequest` API.
///
/// API note: iOS 26 also offers `RecognizeDocumentsRequest` with structured
/// document output; plain text recognition plus our own line assembly keeps
/// the parser input a simple `[String]` and is sufficient for receipts.
struct VisionReceiptRecognizer: ReceiptTextRecognizing {

    func recognizeLines(in image: CGImage) async throws -> [String] {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = [
            Locale.Language(identifier: "id-ID"),
            Locale.Language(identifier: "en-US"),
        ]
        let observations = try await request.perform(on: image)
        let fragments = observations.compactMap { observation -> TextFragment? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return TextFragment(text: candidate.string, box: observation.boundingBox.cgRect)
        }
        return Self.assembleLines(fragments)
    }

    struct TextFragment {
        let text: String
        /// Normalized image coordinates, origin bottom-left (Vision convention).
        let box: CGRect
    }

    /// Groups recognized fragments into visual lines: receipts put the item
    /// name left and the amount right, and Vision often returns them as
    /// separate observations on the same row. Pure — unit-testable.
    static func assembleLines(_ fragments: [TextFragment]) -> [String] {
        guard !fragments.isEmpty else { return [] }
        // Top to bottom (Vision's y grows upward).
        let sorted = fragments.sorted { $0.box.midY > $1.box.midY }

        var lines: [[TextFragment]] = []
        for fragment in sorted {
            if var current = lines.last,
               let anchor = current.first,
               abs(fragment.box.midY - anchor.box.midY)
                   < max(anchor.box.height, fragment.box.height) * 0.6 {
                current.append(fragment)
                lines[lines.count - 1] = current
            } else {
                lines.append([fragment])
            }
        }
        return lines.map { line in
            line.sorted { $0.box.minX < $1.box.minX }
                .map(\.text)
                .joined(separator: "  ")
        }
    }
}
