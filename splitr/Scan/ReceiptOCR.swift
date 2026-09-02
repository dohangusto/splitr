import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
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
        // Preprocess image for OCR: grayscale & contrast enhancement for thermal receipts
        let processedCGImage = preprocessForOCR(image) ?? image
        let requestHandler = VNImageRequestHandler(cgImage: processedCGImage, options: [:])
        let request = VNRecognizeTextRequest()
        request.recognitionLanguages = ["id-ID", "en-US"]
        request.usesLanguageCorrection = true
        request.recognitionLevel = .accurate
        request.minimumTextHeight = 0.008
        request.customWords = [
            "Nasi", "Goreng", "Ayam", "Bakar", "Bebek", "Sate", "Soto", "Bakso",
            "Mie", "Kwetiau", "Bihun", "Es", "Teh", "Manis", "Tawar", "Kopi",
            "Susu", "Jus", "Sambal", "Tahu", "Tempe", "Telur", "Keju", "Coklat",
            "Porsi", "Paket", "Rendang", "Gulai", "Capcay", "Pangsit", "Siomay",
            "Batagor", "Rawon", "Gado-gado", "Lontong", "Sayur", "Kerupuk", "Krupuk",
            "Aqua", "Mineral", "Subtotal", "PB1", "PPN", "Tax", "Service", "Diskon",
            "Total", "Jumlah", "Kembali", "Tunai", "Cash", "QRIS", "Debit", "Order",
            "Meja", "Table", "Pax", "Pcs", "Item", "Gelato", "Spaghetti", "Salted",
            "Egg", "Chkn", "Chicken", "Fries", "French", "Fruit", "Tea", "Ice",
            "Medium", "Large", "Small", "Regular", "Single", "Double", "Cafe",
            "Resto", "Warung", "Kedai", "Bistro", "Kitchen", "Dine-In", "Takeaway"
        ]
        
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

    private func preprocessForOCR(_ cgImage: CGImage) -> CGImage? {
        let ciImage = CIImage(cgImage: cgImage)
        let filter = CIFilter.colorControls()
        filter.inputImage = ciImage
        filter.saturation = 0.0 // Grayscale
        filter.contrast = 1.15  // Boost text contrast
        filter.brightness = 0.05
        guard let output = filter.outputImage else { return nil }
        let context = CIContext()
        return context.createCGImage(output, from: output.extent)
    }
}
