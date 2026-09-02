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

    // MARK: - Multi-line items

    @Test("Item split across lines: name, then qty x unit price")
    func splitLineItem() {
        let parsed = ReceiptParser.parse(text: """
            WARUNG PADANG
            Rendang Daging Spesial
            2 x 25.000
            Es Teh
            5.000
            Subtotal 55.000
            """)

        #expect(parsed.items.count == 3)
        #expect(parsed.items[0].name == "Rendang Daging Spesial")
        #expect(parsed.items[0].price == 25_000)
        #expect(parsed.items[1].name == "Rendang Daging Spesial")
        #expect(parsed.items[2].name == "Es Teh")
        #expect(parsed.items[2].price == 5_000)
        #expect(parsed.unparsedLines.isEmpty)
        #expect(parsed.subtotalMismatch == 0)
    }

    @Test("Split-line item with qty, unit, and disagreeing total flags the rows")
    func splitLineQtyUnitTotal() {
        let parsed = ReceiptParser.parse(text: """
            WARUNG
            Ayam Bakar
            2 x 20.000  45.000
            """)

        #expect(parsed.items.count == 2)
        #expect(parsed.items.allSatisfy { $0.name == "Ayam Bakar" })
        #expect(parsed.items.allSatisfy { $0.price == 20_000 })
        #expect(parsed.items.allSatisfy { $0.needsReview }) // 2×20.000 ≠ 45.000
    }

    @Test("A held name followed by a normal item is still surfaced, not eaten")
    func pendingNameNotEaten() {
        let parsed = ReceiptParser.parse(text: """
            WARUNG
            Mie Ayam    24.000
            Krupuk
            Es Jeruk    8.000
            """)

        #expect(parsed.items.map(\.name) == ["Mie Ayam", "Es Jeruk"])
        #expect(parsed.unparsedLines == ["Krupuk"])
    }

    // MARK: - Subtotal reconciliation

    @Test("Reconciliation: summed items vs printed subtotal, both directions")
    func subtotalReconciliation() {
        let matching = ReceiptParser.parse(text: """
            WARUNG
            Mie Ayam    24.000
            Es Teh      10.000
            Subtotal    34.000
            """)
        #expect(matching.summedSubtotal == 34_000)
        #expect(matching.subtotalMismatch == 0)

        // Printed subtotal higher → something was missed or under-read.
        let missing = ReceiptParser.parse(text: """
            WARUNG
            Mie Ayam    24.000
            Subtotal    34.000
            """)
        #expect(missing.summedSubtotal == 24_000)
        #expect(missing.subtotalMismatch == 10_000)

        // No printed subtotal → nothing to check against.
        let unchecked = ReceiptParser.parse(text: """
            WARUNG
            Mie Ayam    24.000
            """)
        #expect(unchecked.subtotalMismatch == nil)
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

    @Test("Receipt items with various price formats without Rp")
    func noRpFormats() {
        // Test standard with dot thousands separator
        let parsedDot = ReceiptParser.parse(text: "Nasi Goreng 15.000")
        #expect(parsedDot.items.count == 1)
        #expect(parsedDot.items.first?.price == 15_000)

        // Test plain integer
        let parsedPlain = ReceiptParser.parse(text: "Nasi Goreng 15000")
        #expect(parsedPlain.items.count == 1)
        #expect(parsedPlain.items.first?.price == 15_000)

        // Test decimal with two zeros (US/standard style)
        let parsedDecimal = ReceiptParser.parse(text: "Nasi Goreng 15000.00")
        #expect(parsedDecimal.items.count == 1)
        #expect(parsedDecimal.items.first?.price == 15_000)

        // Test decimal with comma and two zeros
        let parsedDecimalComma = ReceiptParser.parse(text: "Nasi Goreng 15000,00")
        #expect(parsedDecimalComma.items.count == 1)
        #expect(parsedDecimalComma.items.first?.price == 15_000)

        // Test short thousands notation (e.g. 15.00 meaning 15k)
        let parsedShort = ReceiptParser.parse(text: "Nasi Goreng 15.00")
        #expect(parsedShort.items.count == 1)
        #expect(parsedShort.items.first?.price == 15_000)
    }

    @Test("Rasea Haji Nawi style receipt")
    func raseaHajiNawiReceipt() {
        let text = """
            Rasea Haji Nawi
            Jakarta Selatan Kita, DKI JAKARTA
            Indonesia
            Waktu Penjualan          Kasir
            21 Jul 2026 15:57    RaseaNawi
            #968F26072100000015    1 Tamu
            -------------------------------
            Item                    Jumlah
            -------------------------------
            Pizza Mie
                   23.000 x1        23.000
            Aqua botol 600 ml
            Tambah Ice
                   10.000 x1        10.000
            Nasi Sarden Cabe
                   37.000 x1        37.000
            -------------------------------
            Subtotal                70.000
            PB1 10%                  7.000
            Grand Total          Rp 77.000
            QRIS by Netzme       Rp 77.000
            """
        let parsed = ReceiptParser.parse(text: text)
        // Pizza Mie (1), Tambah Ice (1), Nasi Sarden Cabe (1).
        // Total items expected: 3
        #expect(parsed.items.count == 3)
        #expect(parsed.items[0].name == "Pizza Mie")
        #expect(parsed.items[0].price == 23_000)
        #expect(parsed.items[1].name == "Tambah Ice")
        #expect(parsed.items[1].price == 10_000)
        #expect(parsed.items[2].name == "Nasi Sarden Cabe")
        #expect(parsed.items[2].price == 37_000)
    }

    @Test("Various quantity patterns: leading digit without x, unit words, numbered lists")
    func variedQuantityPatterns() {
        let text = """
            RESTO NUSANTARA
            1. 2 Nasi Goreng Spesial   50.000
            2. 2 porsi Sate Ayam       60.000
            3. Aqua 3 btl              15.000
            4. Es Teh Manis 2 cup      20.000
            5. Donat Coklat 2 pcs      24.000
            Subtotal                  169.000
            """
        let parsed = ReceiptParser.parse(text: text)
        // 2 Nasi (2) + 2 Sate (2) + 3 Aqua (3) + 2 Es Teh (2) + 2 Donat (2) = 11 items
        #expect(parsed.items.count == 11)
        #expect(parsed.items[0].name == "Nasi Goreng Spesial")
        #expect(parsed.items[0].price == 25_000)
        #expect(parsed.items[2].name == "Sate Ayam")
        #expect(parsed.items[2].price == 30_000)
        #expect(parsed.items[4].name == "Aqua")
        #expect(parsed.items[4].price == 5_000)
        #expect(parsed.items[7].name == "Es Teh Manis")
        #expect(parsed.items[7].price == 10_000)
        #expect(parsed.items[9].name == "Donat Coklat")
        #expect(parsed.items[9].price == 12_000)
        #expect(parsed.printedSubtotal == 169_000)
        #expect(parsed.summedSubtotal == 169_000)
        #expect(parsed.subtotalMismatch == 0)
    }

    @Test("Split-line items with space-separated quantity and unit price")
    func splitLineSpacedQtyUnitPrice() {
        let text = """
            CAFE KITA
            Kopi Susu Gula Aren
            2  18.000  36.000
            Croissant
            2 x 20.000  40.000
            Subtotal 76.000
            """
        let parsed = ReceiptParser.parse(text: text)
        #expect(parsed.items.count == 4)
        #expect(parsed.items[0].name == "Kopi Susu Gula Aren")
        #expect(parsed.items[0].price == 18_000)
        #expect(parsed.items[2].name == "Croissant")
        #expect(parsed.items[2].price == 20_000)
        #expect(parsed.subtotalMismatch == 0)
    }

    @Test("Merchant detection filters out header noise and picks store title")
    func merchantDetectionWithNoise() {
        let text = """
            === STRUK PEMBELIAN ===
            Selamat Datang di
            KOPI JANJI JIWA
            Jl. Sudirman No. 45, Jakarta
            Tanggal: 20/07/2026 14:30
            Order #1234  Kasir: Budi
            ----------------------------
            Kopi Susu Jiwa      20.000
            Subtotal            20.000
            """
        let parsed = ReceiptParser.parse(text: text)
        #expect(parsed.merchantName == "KOPI JANJI JIWA")
        #expect(parsed.items.count == 1)
        #expect(parsed.items[0].name == "Kopi Susu Jiwa")
    }

    @Test("Merchant detection prioritizes larger font size (taller box) at top")
    func merchantDetectionBySize() {
        let rows: [ReceiptRow] = [
            .line(RecognizedText(text: "SELAMAT DATANG", box: NormalizedRect(x: 0.2, y: 0.02, width: 0.6, height: 0.015))),
            .line(RecognizedText(text: "RESTORAN PADANG SEDAP", box: NormalizedRect(x: 0.1, y: 0.05, width: 0.8, height: 0.045))),
            .line(RecognizedText(text: "Jl. Boulevard Raya Blok A", box: NormalizedRect(x: 0.2, y: 0.11, width: 0.6, height: 0.015))),
            .line(RecognizedText(text: "Rendang Sapi 30.000", box: NormalizedRect(x: 0.1, y: 0.20, width: 0.8, height: 0.02))),
            .line(RecognizedText(text: "Subtotal 30.000", box: NormalizedRect(x: 0.1, y: 0.30, width: 0.8, height: 0.02)))
        ]
        let receipt = RecognizedReceipt(rows: rows)
        let parsed = ReceiptParser.parse(receipt)
        #expect(parsed.merchantName == "RESTORAN PADANG SEDAP")
    }

    @Test("Cafe Titik Beku receipt: leading quantity, store title, subtotal")
    func cafeTitikBekuReceipt() {
        let text = """
            Cafe TITIK BEKU
            Jl Harapan Indah Raya BF/20
            Harapan Indah Bekasi
            Telp. 08159355593

            No # : 01.2018.04.08.0235
            Kasir : Administrator
            Tanggal : 08-04-2018 17:54
            No Meja : 19

            Dine-In
            2 FRUIT TEA ICE        30,000
            1 GELATO MEDIUM        28,000
            1 SPAGHETTI SALTED     38,000
            EGG CHKN
            1 FRENCH FRIES         15,000

            Total Order 5 Menu
            SUBTOTAL              111,000
            DISKON                      0
            TOTAL                 111,000

            TERIMA KASIH
            ATAS KUNJUNGAN ANDA
            Review us on
            ZOMATO & GOOGLE
            Follow us @CAFE.BEKU
            """
        let parsed = ReceiptParser.parse(text: text)
        #expect(parsed.merchantName == "Cafe TITIK BEKU")
        // 2 Fruit Tea + 1 Gelato + 1 Spaghetti + 1 French Fries = 5 claimable units
        #expect(parsed.items.count == 5)
        #expect(parsed.items[0].name == "FRUIT TEA ICE")
        #expect(parsed.items[0].price == 15_000)
        #expect(parsed.items[1].name == "FRUIT TEA ICE")
        #expect(parsed.items[1].price == 15_000)
        #expect(parsed.items[2].name == "GELATO MEDIUM")
        #expect(parsed.items[2].price == 28_000)
        #expect(parsed.items[3].price == 38_000)
        #expect(parsed.items[4].name == "FRENCH FRIES")
        #expect(parsed.items[4].price == 15_000)
        #expect(parsed.printedSubtotal == 111_000)
        #expect(parsed.summedSubtotal == 111_000)
        #expect(parsed.subtotalMismatch == 0)
    }

    @Test("Various Tax & Service Charge formats: PB1, SC, Pajak Resto, Biaya Layanan")
    func variedTaxAndServicePatterns() {
        let text = """
            BISTRO NUSANTARA
            Nasi Goreng Wagyu     100.000
            Sate Ayam Madura       50.000
            SUBTOTAL              150.000
            Service Charge 5%       7.500
            PB1 (10%)              15.750
            TOTAL                 173.250
            """
        let parsed = ReceiptParser.parse(text: text)
        #expect(parsed.servicePercent == 5)
        #expect(parsed.taxPercent == 10)
        #expect(parsed.taxBasis == .subtotalPlusService)
        #expect(parsed.printedSubtotal == 150_000)
        #expect(parsed.summedSubtotal == 150_000)
    }

    @Test("PPN 11% and Biaya Layanan")
    func ppn11PercentReceipt() {
        let text = """
            RESTO MODERN
            Steak Ribeye          200.000
            Ice Lemon Tea          20.000
            Total Sebelum Pajak   220.000
            Biaya Layanan          11.000
            PPN 11%                25.410
            Total                 256.410
            """
        let parsed = ReceiptParser.parse(text: text)
        #expect(parsed.servicePercent == 5) // 11.000 / 220.000 = 5%
        #expect(parsed.taxPercent == 11)
        #expect(parsed.taxBasis == .subtotalPlusService) // 11% of (220.000 + 11.000) = 25.410
        #expect(parsed.printedSubtotal == 220_000)
    }
}


