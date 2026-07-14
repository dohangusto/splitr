import CoreGraphics
import Foundation
import Testing
import SplitBillCore
@testable import splitr

/// Parser tests run on raw recognized-text fixtures — no camera, no Vision,
/// fully simulator/CI-safe.
@Suite("ReceiptParser")
struct ReceiptParserTests {

    @Test("Clean receipt: items, rates, and tax-on-subtotal+service basis")
    func cleanReceiptServiceTaxed() {
        let parsed = ReceiptParser.parse(text: """
            WARUNG TEKKO
            Jl. Sudirman 12, Jakarta

            Nasi Goreng Kambing    55.000
            2x Sate Ayam           70.000
            Es Teh Manis           10.000

            Subtotal              135.000
            Service 5%              6.750
            PB1 10%                14.175
            TOTAL                 155.925
            """)

        #expect(parsed.merchantName == "WARUNG TEKKO")
        #expect(parsed.items.count == 3)
        #expect(parsed.items[0].name == "Nasi Goreng Kambing")
        #expect(parsed.items[0].price == 55_000)
        #expect(parsed.items[0].qty == 1)
        #expect(parsed.items[1].name == "Sate Ayam")
        #expect(parsed.items[1].qty == 2)
        #expect(parsed.items[1].price == 35_000) // 70.000 line total / 2
        #expect(parsed.items[1].needsReview == false)
        #expect(parsed.items[2].price == 10_000)
        #expect(parsed.printedSubtotal == 135_000)
        #expect(parsed.servicePercent == 5)
        #expect(parsed.taxPercent == 10)
        // 14.175 == 10% of (135.000 + 6.750) → tax was computed on subtotal + service.
        #expect(parsed.taxBasis == .subtotalPlusService)
        #expect(parsed.unparsedLines.isEmpty)
    }

    @Test("Service not taxed: amounts prove tax-on-subtotal basis without % labels")
    func serviceNotTaxed() {
        let parsed = ReceiptParser.parse(text: """
            BAKMI GM
            Bakmi Spesial       32.000
            Pangsit Goreng      26.000
            Sub Total           58.000
            Service Charge       2.900
            Tax                  5.800
            Total               66.700
            """)

        #expect(parsed.items.count == 2)
        #expect(parsed.printedSubtotal == 58_000)
        // No % printed anywhere — both rates recovered from the amounts.
        #expect(parsed.servicePercent == 5)
        #expect(parsed.taxPercent == 10)
        // 5.800 == 10% of 58.000 (not of 60.900) → tax on subtotal only.
        #expect(parsed.taxBasis == .subtotal)
    }

    @Test("Abbreviated names, '@' quantity pricing, Rp prefixes, decimal tails")
    func abbreviatedAndAtQty() {
        let parsed = ReceiptParser.parse(text: """
            KOPI KENANGAN
            KopKen Mantan 2 @22.000  44.000
            Croffle Choc             Rp 28.000,00
            SUBTOTAL                 72.000
            PPN 10%                   7.200
            """)

        #expect(parsed.items.count == 2)
        #expect(parsed.items[0].name == "KopKen Mantan")
        #expect(parsed.items[0].qty == 2)
        #expect(parsed.items[0].price == 22_000) // from the @unit, not the total
        #expect(parsed.items[1].name == "Croffle Choc")
        #expect(parsed.items[1].price == 28_000) // Rp prefix + ,00 tail stripped
        #expect(parsed.taxPercent == 10)
        // No service charge → both bases coincide; basis stays undetermined.
        #expect(parsed.taxBasis == nil)
    }

    @Test("Trailing x2 marker with a non-divisible total flags the row")
    func trailingQtyNonDivisible() {
        let parsed = ReceiptParser.parse(text: """
            SOLARIA
            Ayam Lada Hitam x2   90.001
            """)

        #expect(parsed.items.count == 1)
        #expect(parsed.items[0].qty == 2)
        #expect(parsed.items[0].price == 45_000) // floor of 90.001 / 2
        #expect(parsed.items[0].needsReview == true) // …but flagged for review
    }

    @Test("Discount lines never become items and are surfaced, not dropped")
    func discountLine() {
        let parsed = ReceiptParser.parse(text: """
            SOLARIA
            Ayam Lada Hitam     45.000
            Nasi Putih           8.000
            Diskon Member       -5.000
            Subtotal            48.000
            """)

        #expect(parsed.items.count == 2)
        #expect(parsed.items.allSatisfy { ($0.price ?? 0) > 0 })
        #expect(parsed.unparsedLines == ["Diskon Member       -5.000"])
        #expect(parsed.printedSubtotal == 48_000)
    }

    @Test("Unlabeled negative amounts are surfaced too")
    func unlabeledNegative() {
        let parsed = ReceiptParser.parse(text: """
            WARUNG
            Mie Ayam    24.000
            Member      (2.000)
            """)

        #expect(parsed.items.count == 1)
        #expect(parsed.unparsedLines == ["Member      (2.000)"])
    }

    @Test("Messy receipt degrades gracefully: partial parse, nothing dropped silently")
    func messyReceipt() {
        let parsed = ReceiptParser.parse(text: """
            === S T R U K ===
            xx##!!@@
            Mie Ayam Bakso 24.000
            Krupuk
            ????
            TOTAL 24.000
            Terima kasih ~ sampai jumpa
            """)

        // One clean item; the price-less "Krupuk" is surfaced for manual
        // entry; decoration and footer courtesy lines are ignored.
        #expect(parsed.items.count == 1)
        #expect(parsed.items[0].name == "Mie Ayam Bakso")
        #expect(parsed.items[0].price == 24_000)
        #expect(parsed.unparsedLines.contains("Krupuk"))
        #expect(parsed.taxPercent == nil)
        #expect(parsed.taxBasis == nil)
    }

    @Test("Empty and garbage-only input parse to an empty result")
    func emptyInput() {
        #expect(ReceiptParser.parse(text: "").items.isEmpty)
        let garbage = ReceiptParser.parse(text: "***\n---\n   \n===")
        #expect(garbage.items.isEmpty)
        #expect(garbage.merchantName == nil)
        #expect(garbage.unparsedLines.isEmpty)
    }

    @Test("Money token parsing", arguments: [
        ("55.000", 55_000),
        ("55.000,00", 55_000),
        ("Rp 8.000", 8_000),
        ("24000", 24_000),
        ("1.234.500", 1_234_500),
    ])
    func moneyValues(input: String, expected: Int) {
        #expect(ReceiptParser.trailingMoney(in: "Item \(input)")?.value == expected)
    }

    @Test("Line assembly joins same-row fragments left to right, top to bottom")
    func lineAssembly() {
        typealias Fragment = VisionReceiptRecognizer.TextFragment
        // Vision-style normalized boxes, origin bottom-left: the name and
        // price of one row arrive as separate observations.
        let fragments = [
            Fragment(text: "55.000", box: CGRect(x: 0.7, y: 0.80, width: 0.2, height: 0.04)),
            Fragment(text: "Nasi Goreng", box: CGRect(x: 0.05, y: 0.81, width: 0.4, height: 0.04)),
            Fragment(text: "Es Teh", box: CGRect(x: 0.05, y: 0.70, width: 0.3, height: 0.04)),
            Fragment(text: "10.000", box: CGRect(x: 0.7, y: 0.69, width: 0.2, height: 0.04)),
        ]
        #expect(VisionReceiptRecognizer.assembleLines(fragments)
            == ["Nasi Goreng  55.000", "Es Teh  10.000"])
    }
}
