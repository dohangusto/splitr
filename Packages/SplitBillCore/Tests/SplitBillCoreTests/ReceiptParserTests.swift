import Testing
@testable import SplitBillCore

/// Parser tests run on recognized-text fixtures — no camera, no Vision,
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
        // Quantity explodes at parse time: 2x Sate → two unit rows.
        #expect(parsed.items.count == 4)
        #expect(parsed.items[0].name == "Nasi Goreng Kambing")
        #expect(parsed.items[0].price == 55_000)
        #expect(parsed.items[1].name == "Sate Ayam")
        #expect(parsed.items[2].name == "Sate Ayam")
        #expect(parsed.items[1].price == 35_000) // 70.000 line total / 2
        #expect(parsed.items[1].qty == 1)
        #expect(parsed.items[1].needsReview == false)
        #expect(parsed.items[3].price == 10_000)
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

        #expect(parsed.items.count == 3)
        #expect(parsed.items[0].name == "KopKen Mantan")
        #expect(parsed.items[1].name == "KopKen Mantan")
        #expect(parsed.items[0].price == 22_000) // from the @unit, not the total
        #expect(parsed.items[2].name == "Croffle Choc")
        #expect(parsed.items[2].price == 28_000) // Rp prefix + ,00 tail stripped
        #expect(parsed.taxPercent == 10)
        // No service charge → both bases coincide; basis stays undetermined.
        #expect(parsed.taxBasis == nil)
    }

    @Test("Trailing x2 marker with a non-divisible total flags both unit rows")
    func trailingQtyNonDivisible() {
        let parsed = ReceiptParser.parse(text: """
            SOLARIA
            Ayam Lada Hitam x2   90.001
            """)

        #expect(parsed.items.count == 2)
        #expect(parsed.items.allSatisfy { $0.price == 45_000 }) // floor of 90.001 / 2
        #expect(parsed.items.allSatisfy { $0.needsReview }) // …but flagged for review
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
        ("15.000,-", 15_000),
        ("1.234.500", 1_234_500),
    ])
    func moneyValues(input: String, expected: Int) {
        #expect(ReceiptParser.trailingMoney(in: "Item \(input)")?.value == expected)
    }

    // MARK: - Structured table rows

    @Test("Table row with name | qty | price cells uses the structure")
    func tableRowNameQtyPrice() {
        let receipt = RecognizedReceipt(rows: [
            .line(RecognizedText(text: "WARUNG TEKKO")),
            .tableRow([
                RecognizedText(text: "Sate Ayam"),
                RecognizedText(text: "2"),
                RecognizedText(text: "70.000"),
            ]),
            .tableRow([
                RecognizedText(text: "Es Teh Manis"),
                RecognizedText(text: "1"),
                RecognizedText(text: "10.000"),
            ]),
        ])
        let parsed = ReceiptParser.parse(receipt)

        #expect(parsed.merchantName == "WARUNG TEKKO")
        #expect(parsed.items.count == 3)
        #expect(parsed.items[0].name == "Sate Ayam")
        #expect(parsed.items[0].price == 35_000) // 70.000 total / qty 2
        #expect(parsed.items[2].name == "Es Teh Manis")
        #expect(parsed.items[2].price == 10_000)
    }

    @Test("Table row with unit and total columns prefers the agreeing unit")
    func tableRowUnitAndTotal() {
        let receipt = RecognizedReceipt(rows: [
            .tableRow([
                RecognizedText(text: "Kopi Susu"),
                RecognizedText(text: "3"),
                RecognizedText(text: "18.000"),
                RecognizedText(text: "54.000"),
            ])
        ])
        let parsed = ReceiptParser.parse(receipt)

        #expect(parsed.items.count == 3)
        #expect(parsed.items.allSatisfy { $0.price == 18_000 })
        #expect(parsed.items.allSatisfy { !$0.needsReview })
    }

    @Test("Summary rows inside the table still classify as rates, not items")
    func tableSummaryRows() {
        let receipt = RecognizedReceipt(rows: [
            .tableRow([RecognizedText(text: "Bakmi Spesial"), RecognizedText(text: "32.000")]),
            .tableRow([RecognizedText(text: "Subtotal"), RecognizedText(text: "32.000")]),
            .tableRow([RecognizedText(text: "PB1 10%"), RecognizedText(text: "3.200")]),
        ])
        let parsed = ReceiptParser.parse(receipt)

        #expect(parsed.items.count == 1)
        #expect(parsed.printedSubtotal == 32_000)
        #expect(parsed.taxPercent == 10)
    }

    @Test("Geometry rides through to drafts for photo highlighting")
    func geometryPreserved() {
        let box = NormalizedRect(x: 0.1, y: 0.3, width: 0.8, height: 0.04)
        let receipt = RecognizedReceipt(rows: [
            .line(RecognizedText(text: "Mie Ayam 24.000", box: box, confidence: 0.42))
        ])
        let parsed = ReceiptParser.parse(receipt)

        #expect(parsed.items.count == 1)
        #expect(parsed.items[0].sourceBox == box)
        #expect(parsed.items[0].confidence == 0.42)
    }

    // MARK: - Row assembly & table dedup

    @Test("Line assembly joins same-row fragments left to right, top to bottom")
    func lineAssembly() {
        // Normalized boxes, origin top-left (y grows downward): the name and
        // price of one row arrive as separate fragments.
        let fragments = [
            RecognizedText(text: "55.000", box: NormalizedRect(x: 0.7, y: 0.16, width: 0.2, height: 0.04)),
            RecognizedText(text: "Nasi Goreng", box: NormalizedRect(x: 0.05, y: 0.15, width: 0.4, height: 0.04)),
            RecognizedText(text: "Es Teh", box: NormalizedRect(x: 0.05, y: 0.26, width: 0.3, height: 0.04)),
            RecognizedText(text: "10.000", box: NormalizedRect(x: 0.7, y: 0.27, width: 0.2, height: 0.04)),
        ]
        #expect(RecognizedReceipt.assembleLines(fragments).map(\.text)
            == ["Nasi Goreng  55.000", "Es Teh  10.000"])
    }

    @Test("Free lines inside a table region are replaced by the table's rows")
    func tableDeduplicatesLines() {
        let tableRegion = NormalizedRect(x: 0, y: 0.4, width: 1, height: 0.3)
        let receipt = RecognizedReceipt(
            lines: [
                RecognizedText(text: "WARUNG", box: NormalizedRect(x: 0.3, y: 0.1, width: 0.4, height: 0.05)),
                // Same content as the table row below — must not double-count.
                RecognizedText(text: "Mie Ayam  24.000", box: NormalizedRect(x: 0.1, y: 0.5, width: 0.8, height: 0.05)),
            ],
            tables: [
                RecognizedTable(
                    rows: [[
                        RecognizedText(text: "Mie Ayam", box: NormalizedRect(x: 0.1, y: 0.5, width: 0.4, height: 0.05)),
                        RecognizedText(text: "24.000", box: NormalizedRect(x: 0.6, y: 0.5, width: 0.3, height: 0.05)),
                    ]],
                    region: tableRegion
                )
            ]
        )
        let parsed = ReceiptParser.parse(receipt)

        #expect(parsed.merchantName == "WARUNG")
        #expect(parsed.items.count == 1)
        #expect(parsed.items[0].price == 24_000)
    }
}
