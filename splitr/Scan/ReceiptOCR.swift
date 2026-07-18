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
        var request = RecognizeDocumentsRequest()
        // Correction "fixes" prices and Indonesian menu names into English
        // words — the two things we need exact. Never enable it.
        request.textRecognitionOptions.useLanguageCorrection = false
        request.textRecognitionOptions.automaticallyDetectLanguage = false
        request.textRecognitionOptions.recognitionLanguages = [
            Locale.Language(identifier: "id-ID"),
            Locale.Language(identifier: "en-US"),
        ]
        // Receipt type is small relative to the frame; default is too coarse.
        request.textRecognitionOptions.minimumTextHeightFraction = 0.005
        request.textRecognitionOptions.customWords = [
            "Subtotal", "Total", "PB1", "Pajak", "Ppn", "Service", "Svc",
            "Tunai", "Kembali", "Kembalian", "Diskon", "Qty", "Bungkus",
            "Dine In", "Take Away",
        ]

        let observations = try await request.perform(on: image)
        guard let document = observations.first?.document else {
            return RecognizedReceipt(rows: [])
        }

        // Vision may still split one visual receipt row (name left, price
        // right) into separate line observations; assembleLines re-joins
        // them by geometry before parsing.
        let lines = RecognizedReceipt.assembleLines(
            document.text.lines.compactMap(Self.recognizedText(from:))
        )
        let tables = document.tables.map { table in
            RecognizedTable(
                rows: table.rows.map { row in
                    row.compactMap { cell in
                        let text = cell.content.text
                        let transcript = text.transcript
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !transcript.isEmpty else { return nil }
                        return SplitBillCore.RecognizedText(
                            text: transcript,
                            box: Self.rect(from: text.boundingRegion),
                            confidence: text.lines.map { Double($0.confidence) }.min()
                        )
                    }
                },
                region: Self.rect(from: table.boundingRegion)
            )
        }
        return RecognizedReceipt(lines: lines, tables: tables)
    }

    private static func recognizedText(
        from observation: RecognizedTextObservation
    ) -> SplitBillCore.RecognizedText? {
        let transcript = observation.transcript
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else { return nil }
        return SplitBillCore.RecognizedText(
            text: transcript,
            box: rect(from: observation.boundingRegion),
            confidence: Double(observation.confidence)
        )
    }

    /// Vision regions are normalized polygons with a bottom-left origin;
    /// Core geometry is a top-left-origin `NormalizedRect`.
    private static func rect(from region: NormalizedRegion) -> SplitBillCore.NormalizedRect? {
        let points = region.normalizedPoints
        guard !points.isEmpty else { return nil }
        let xs = points.map { Double($0.x) }
        let ys = points.map { Double($0.y) }
        let minX = xs.min()!, maxX = xs.max()!
        let minY = ys.min()!, maxY = ys.max()!
        return SplitBillCore.NormalizedRect(
            x: minX,
            y: 1 - maxY, // flip to top-left origin
            width: maxX - minX,
            height: maxY - minY
        )
    }
}
