import SplitBillCore
import Testing
import UIKit
@testable import splitr

/// Parsing tests against fixture images: image → Vision OCR → Core parse.
/// The scan pipeline is camera-independent by design — these render
/// deterministic receipt fixtures at test time (a rendered receipt is the
/// honest fixture we can make reproducible; real-paper photos need the
/// device flow). Deliberately skips the perspective-correction step: that
/// exercises Apple's document segmentation, whose output on synthetic
/// images is nondeterministic and isn't what these tests pin.
/// Serialized: concurrent Vision requests contend and flake.
@Suite("Receipt scan pipeline", .serialized)
struct ReceiptScanPipelineTests {

    @Test("Rendered receipt fixture parses to items and rates")
    func rendersAndParses() async throws {
        let image = Self.renderReceipt(lines: [
            "WARUNG TEKKO",
            "",
            "Nasi Goreng Kambing      55.000",
            "Es Teh Manis             10.000",
            "",
            "Subtotal                 65.000",
            "PB1 10%                   6.500",
            "TOTAL                    71.500",
        ])

        let recognized = try await VisionReceiptRecognizer().recognize(image.cgImage!)
        let parsed = ReceiptParser.parse(recognized)

        #expect(parsed.items.count == 2)
        #expect(parsed.items.contains { $0.name.localizedCaseInsensitiveContains("Nasi Goreng") && $0.price == 55_000 })
        #expect(parsed.items.contains { $0.name.localizedCaseInsensitiveContains("Es Teh") && $0.price == 10_000 })
        #expect(parsed.printedSubtotal == 65_000)
        #expect(parsed.taxPercent == 10)
        // The parse reconciles: summed items match the printed subtotal.
        #expect(parsed.subtotalMismatch == 0)
        // Geometry must survive the pipeline — the edit screen highlights
        // each row's source region on the photo.
        #expect(parsed.items.allSatisfy { $0.sourceBox != nil })
        #expect(parsed.items.allSatisfy { $0.confidence != nil })
    }

    @Test("Fixture whose items don't sum to the printed subtotal reports the mismatch")
    func subtotalMismatchSurfaces() async throws {
        // Printed subtotal says 99.000; the two items sum to 65.000 —
        // as if OCR missed a line. Reconciliation must expose the gap.
        let image = Self.renderReceipt(lines: [
            "WARUNG TEKKO",
            "",
            "Nasi Goreng Kambing      55.000",
            "Es Teh Manis             10.000",
            "",
            "Subtotal                 99.000",
        ])

        let recognized = try await VisionReceiptRecognizer().recognize(image.cgImage!)
        let parsed = ReceiptParser.parse(recognized)

        #expect(parsed.printedSubtotal == 99_000)
        #expect(parsed.summedSubtotal == 65_000)
        #expect(parsed.subtotalMismatch == 34_000)
    }

    @Test("Blank image parses to zero items — a normal outcome, not an error")
    func blankImageParsesEmpty() async throws {
        let image = Self.renderReceipt(lines: [])

        let recognized = try await VisionReceiptRecognizer().recognize(image.cgImage!)
        let parsed = ReceiptParser.parse(recognized)

        #expect(parsed.items.isEmpty)
        #expect(parsed.merchantName == nil)
    }

    /// Renders receipt-style monospaced text as a white "paper" slip on a
    /// dark background, portrait, with type small relative to the frame —
    /// the shape document segmentation expects from a real shot.
    private static func renderReceipt(lines: [String]) -> UIImage {
        let size = CGSize(width: 1080, height: 1620)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.darkGray.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.white.setFill()
            context.fill(CGRect(x: 60, y: 120, width: size.width - 120, height: size.height - 240))
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 34, weight: .regular),
                .foregroundColor: UIColor.black,
            ]
            for (index, line) in lines.enumerated() {
                (line as NSString).draw(
                    at: CGPoint(x: 90, y: 200 + CGFloat(index) * 56),
                    withAttributes: attributes
                )
            }
        }
    }
}
