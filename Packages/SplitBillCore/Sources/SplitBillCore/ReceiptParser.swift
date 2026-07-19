import Foundation

/// Result of parsing a recognized receipt. Everything is best-effort:
/// nil means "not detected — let the user fill it in on the review form".
/// This is a draft, never a `Bill`; nothing here reaches members without
/// passing through the edit screen.
public struct ParsedReceipt: Sendable, Hashable {
    public var merchantName: String?
    /// One draft per claimable unit — quantity is already exploded
    /// (a "2x Sate" line yields two drafts), matching `BillItem` granularity.
    public var items: [DraftItem] = []
    /// Detected PB1 percentage (e.g. 10). Unconfirmed until reviewed.
    public var taxPercent: Int?
    /// Detected service charge percentage (e.g. 5). Unconfirmed until reviewed.
    public var servicePercent: Int?
    /// Only set when the amounts prove which base the tax was computed on;
    /// nil when there is no service charge to disambiguate.
    public var taxBasis: TaxBasis?
    /// The receipt's printed subtotal, when found (verification aid).
    public var printedSubtotal: Int?
    /// Content lines the parser could not turn into items — surfaced to the
    /// user for manual entry, never dropped silently.
    public var unparsedLines: [String] = []

    public init() {}

    // MARK: Subtotal reconciliation — the pipeline's strongest check.
    // Per-field confidence says "Vision was unsure about this glyph";
    // a subtotal mismatch says "the total doesn't add up" — an item was
    // missed, double-read, or mispriced, known without any human checking.
    // The edit screen steers attention by this, not by confidence alone.

    /// Sum of the parsed line items, in whole rupiah.
    public var summedSubtotal: Int {
        items.reduce(0) { $0 + ($1.price ?? 0) * $1.qty }
    }

    /// `printedSubtotal - summedSubtotal`: zero when the parse reconciles,
    /// positive when items are missing or under-read, negative when
    /// something was double-read or over-read. nil when the receipt
    /// printed no subtotal to check against.
    public var subtotalMismatch: Int? {
        printedSubtotal.map { $0 - summedSubtotal }
    }
}

/// Pure, hardware-free receipt parser for Indonesian receipts. Input is
/// recognized rows (top to bottom) — free lines and/or structured table
/// rows; no camera, no Vision.
///
/// Handles: `Rp` prefixes, dot/comma thousand separators, trailing ",00"
/// decimals, `2x` / `x2` / `2 @unit` quantity markers, table rows with
/// separate name/qty/price cells, abbreviated names, discount lines
/// (excluded from items, surfaced), and PB1/service/subtotal detection
/// including which base the tax was computed on.
public enum ReceiptParser {

    public static func parse(text: String) -> ParsedReceipt {
        parse(lines: text.components(separatedBy: .newlines))
    }

    public static func parse(lines: [String]) -> ParsedReceipt {
        parse(RecognizedReceipt(rows: lines.map { .line(RecognizedText(text: $0)) }))
    }

    public static func parse(_ receipt: RecognizedReceipt) -> ParsedReceipt {
        var result = ParsedReceipt()
        var taxAmount: Int?
        var serviceAmount: Int?
        var sawItem = false
        var sawTotal = false

        // One item does not always equal one line: receipts split an item
        // into a name line followed by a qty/price line ("Nasi Goreng" then
        // "2 x 25.000"). A no-amount line is held here until the next line
        // decides whether it was a name waiting for its price.
        var pending: (name: String, box: NormalizedRect?, confidence: Double?, afterItems: Bool)?
        func flushPending() {
            // Matches the single-line behavior: price-less text between
            // items is surfaced for manual entry; header noise is not.
            if let p = pending, p.afterItems {
                result.unparsedLines.append(p.name)
            }
            pending = nil
        }

        for row in receipt.rows {
            let line = row.joinedText.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, line.rangeOfCharacter(from: .alphanumerics) != nil else {
                continue // blank or pure decoration (=== ---- ***)
            }
            let lowered = line.lowercased()

            // Summary lines. Order matters: "sub total" contains "total".
            if contains(lowered, any: Self.subtotalKeywords) {
                result.printedSubtotal = trailingMoney(in: line)?.value ?? result.printedSubtotal
                continue
            }
            if contains(lowered, any: Self.taxKeywords) {
                taxAmount = trailingMoney(in: line)?.value ?? taxAmount
                result.taxPercent = percent(in: line) ?? result.taxPercent
                continue
            }
            if contains(lowered, any: Self.serviceKeywords) {
                serviceAmount = trailingMoney(in: line)?.value ?? serviceAmount
                result.servicePercent = percent(in: line) ?? result.servicePercent
                continue
            }
            if contains(lowered, any: Self.discountKeywords) {
                result.unparsedLines.append(line) // never silently drop money off the bill
                continue
            }
            if contains(lowered, any: Self.totalKeywords) {
                flushPending()
                sawTotal = true
                continue
            }
            if contains(lowered, any: Self.ignoreKeywords) {
                continue
            }

            // Item rows: structured table row first, then name + trailing amount.
            if !sawTotal {
                if case .tableRow(let cells) = row, let items = parseTableRow(cells) {
                    flushPending()
                    result.items.append(contentsOf: items)
                    sawItem = true
                    continue
                }
                if let money = trailingMoney(in: line) {
                    if money.value < 0 {
                        flushPending()
                        result.unparsedLines.append(line) // unlabeled discount
                    } else if let p = pending, let items = parseContinuation(
                        line: line, money: money, pendingName: p.name,
                        box: row.box ?? p.box,
                        confidence: [row.confidence, p.confidence].compactMap { $0 }.min()
                    ) {
                        // Split-line item: the previous line was the name,
                        // this one is its qty/price.
                        pending = nil
                        result.items.append(contentsOf: items)
                        sawItem = true
                    } else if let items = parseItems(
                        line: line, money: money,
                        box: row.box, confidence: row.confidence
                    ) {
                        flushPending()
                        result.items.append(contentsOf: items)
                        sawItem = true
                    } else {
                        flushPending()
                        result.unparsedLines.append(line)
                    }
                    continue
                }
            }

            // Text without an amount.
            if !sawItem && !sawTotal && result.merchantName == nil {
                // Header block: first line is the merchant, the rest
                // (address, phone, date) is noise unless the next line
                // turns out to be its price.
                result.merchantName = line
            } else if !sawTotal {
                // Might be a name whose price is on the next line; held,
                // not yet given up on.
                flushPending()
                pending = (line, row.box, row.confidence, sawItem)
            }
            // After the total line, footer text is ignorable.
        }
        flushPending()

        resolveRates(
            into: &result,
            taxAmount: taxAmount,
            serviceAmount: serviceAmount
        )
        return result
    }

    // MARK: - Table rows

    /// Structured extraction from a table row: name cell(s) + optional qty
    /// cell + price cell(s), as `RecognizeDocumentsRequest` splits receipt
    /// columns. Returns nil (fall back to line parsing) when the shape
    /// doesn't fit.
    private static func parseTableRow(_ cells: [RecognizedText]) -> [DraftItem]? {
        guard cells.count >= 2 else { return nil }

        var nameParts: [String] = []
        var qty = 1
        var explicitUnit: Int?
        var amounts: [Int] = []

        for cell in cells {
            let text = cell.text.trimmingCharacters(in: .whitespaces)
            if text.isEmpty { continue }
            // "@22.000" — explicit unit price marker.
            if let match = text.firstMatch(of: /^@\s*(Rp\.?\s*)?([\d.,]+)$/),
               let unit = moneyValue(String(match.2)) {
                explicitUnit = unit
            }
            // Pure quantity: "2", "2x", "x2".
            else if let match = text.wholeMatch(of: /[xX]?(\d{1,2})[xX]?/),
                    let q = Int(match.1), (1...99).contains(q) {
                qty = q
            }
            // Money cell: "55.000", "Rp 55.000".
            else if let match = text.wholeMatch(of: /(?:Rp\.?\s*|IDR\s*)?(-?\(?[\d.,]+\)?)(?:\s*,-)?/),
                    let value = moneyValue(String(match.1)), abs(value) >= 100 {
                amounts.append(value)
            }
            // Name cell (possibly with an inline qty marker).
            else {
                nameParts.append(text)
            }
        }

        guard !amounts.isEmpty else { return nil }
        if amounts.contains(where: { $0 < 0 }) { return nil } // discount → fall back, surfaced
        var name = nameParts.joined(separator: " ")

        // Inline qty in the name cell: "2x Sate Ayam" / "Sate Ayam x2".
        if qty == 1 {
            if let match = name.firstMatch(of: /^(\d{1,2})\s*[xX]\s+/), let q = Int(match.1) {
                qty = q
                name.removeSubrange(match.range)
            } else if let match = name.firstMatch(of: /\s[xX]\s?(\d{1,2})\s*$/), let q = Int(match.1) {
                qty = q
                name.removeSubrange(match.range)
            }
        }
        name = cleaned(name)
        guard !name.isEmpty else { return nil }

        var unitPrice: Int
        var needsReview = false
        if let explicitUnit {
            unitPrice = explicitUnit
        } else if amounts.count >= 2, qty > 1, amounts.first! * qty == amounts.last! {
            // [unit, total] columns agree.
            unitPrice = amounts.first!
        } else {
            // Single amount (or ambiguous): treat the last as the line total.
            (unitPrice, needsReview) = unitFromTotal(amounts.last!, qty: qty)
        }

        let box = cells.compactMap(\.box).reduce(nil as NormalizedRect?) { acc, next in
            acc.map { $0.union(next) } ?? next
        }
        let confidence = cells.compactMap(\.confidence).min()
        return explode(
            name: name, unitPrice: unitPrice, qty: qty,
            needsReview: needsReview, box: box, confidence: confidence
        )
    }

    // MARK: - Item lines

    /// Parses the price line of a split-line item: the previous line was a
    /// bare name, this line carries only quantity and money ("25.000",
    /// "2 x 25.000", "2 x 25.000  50.000", "2 @25.000  50.000"). Returns
    /// nil when the line has its own name — then it's a normal item and the
    /// pending name was something else.
    private static func parseContinuation(
        line: String,
        money: (value: Int, range: Range<String.Index>),
        pendingName: String,
        box: NormalizedRect?,
        confidence: Double?
    ) -> [DraftItem]? {
        guard money.value >= 100 else { return nil }
        let rest = cleaned(String(line[..<money.range.lowerBound]))

        var qty = 1
        var unitPrice = money.value
        var needsReview = false

        if rest.isEmpty {
            // Bare price → single unit.
        } else if let match = rest.wholeMatch(of: /(\d{1,2})\s*[xX]/), let q = Int(match.1) {
            // "2 x 25.000" — receipt convention reads as qty × unit price.
            // If that reading is wrong, subtotal reconciliation flags it.
            qty = q
        } else if let match = rest.wholeMatch(of: /(\d{1,2})\s*[xX@]\s*(?:Rp\.?\s*)?([\d.,]+)/),
                  let q = Int(match.1), let unit = moneyValue(String(match.2)) {
            // "2 x 25.000  [50.000]" — qty and unit, trailing money is the
            // line total; flag when they disagree.
            qty = q
            unitPrice = unit
            needsReview = unit * q != money.value
        } else {
            return nil // has its own name — not a continuation
        }
        guard qty >= 1 else { return nil }
        return explode(
            name: pendingName, unitPrice: unitPrice, qty: qty,
            needsReview: needsReview, box: box, confidence: confidence
        )
    }

    private static func parseItems(
        line: String,
        money: (value: Int, range: Range<String.Index>),
        box: NormalizedRect?,
        confidence: Double?
    ) -> [DraftItem]? {
        // Amounts below Rp 100 are almost certainly not prices.
        guard money.value >= 100 else { return nil }

        var name = String(line[..<money.range.lowerBound])
        var qty = 1
        var unitPrice = money.value
        var needsReview = false

        // "Nama 2 @22.000 [44.000]" — qty with explicit unit price.
        if let match = name.firstMatch(of: /(\d{1,2})\s*@\s*(Rp\.?\s*)?([\d.,]+)/),
           let unit = moneyValue(String(match.3)) {
            qty = Int(match.1) ?? 1
            unitPrice = unit
            name.removeSubrange(match.range)
        }
        // "2x Nama [70.000]" — leading qty; amount is the line total.
        else if let match = name.firstMatch(of: /^(\d{1,2})\s*[xX]\s+/) {
            qty = Int(match.1) ?? 1
            name.removeSubrange(match.range)
            (unitPrice, needsReview) = unitFromTotal(money.value, qty: qty)
        }
        // "Nama x2 [70.000]" — trailing qty marker.
        else if let match = name.firstMatch(of: /\s[xX]\s?(\d{1,2})\s*$/) {
            qty = Int(match.1) ?? 1
            name.removeSubrange(match.range)
            (unitPrice, needsReview) = unitFromTotal(money.value, qty: qty)
        }

        let cleanedName = cleaned(name)
        guard !cleanedName.isEmpty, qty >= 1 else { return nil }
        return explode(
            name: cleanedName, unitPrice: unitPrice, qty: qty,
            needsReview: needsReview, box: box, confidence: confidence
        )
    }

    /// Quantity explosion: one draft per claimable unit, per the data model.
    private static func explode(
        name: String, unitPrice: Int, qty: Int,
        needsReview: Bool, box: NormalizedRect?, confidence: Double?
    ) -> [DraftItem] {
        (0..<qty).map { _ in
            DraftItem(
                name: name, price: unitPrice, qty: 1,
                needsReview: needsReview, sourceBox: box, confidence: confidence
            )
        }
    }

    private static func cleaned(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".…-:*"))
            .trimmingCharacters(in: .whitespaces)
    }

    private static func unitFromTotal(_ total: Int, qty: Int) -> (Int, Bool) {
        guard qty > 1 else { return (total, false) }
        if total % qty == 0 {
            return (total / qty, false)
        }
        return (total / qty, true) // not divisible — flag for review
    }

    // MARK: - Money

    /// Finds the amount at the end of a line ("Sate Ayam  70.000",
    /// "Es Teh Rp 10.000", "Diskon -5.000"). Returns nil if the line
    /// doesn't end in something money-shaped.
    public static func trailingMoney(in line: String) -> (value: Int, range: Range<String.Index>)? {
        let pattern = /(?:Rp\.?\s*|IDR\s*)?(-?\(?\d{1,3}(?:[.,]\d{3})+(?:[.,]\d{2})?\)?|-?\(?\d{4,}\)?)\s*(?:,-)?\s*$/
        guard let match = line.firstMatch(of: pattern),
              let value = moneyValue(String(match.1)) else { return nil }
        return (value, match.range)
    }

    /// "55.000" → 55000, "55.000,00" → 55000, "Rp 8.000" → 8000,
    /// "(5.000)" / "-5.000" → -5000, "24000" → 24000.
    public static func moneyValue(_ raw: String) -> Int? {
        var s = raw.trimmingCharacters(in: .whitespaces)
        if s.hasSuffix(",-") { s = String(s.dropLast(2)) }
        var negative = false
        if s.hasPrefix("-") { negative = true; s.removeFirst() }
        if s.hasPrefix("("), s.hasSuffix(")") {
            negative = true
            s = String(s.dropFirst().dropLast())
        }
        // Trailing 2-digit decimals after grouped thousands: "55.000,00".
        if let match = s.firstMatch(of: /^(\d{1,3}(?:[.,]\d{3})+)[.,]\d{2}$/) {
            s = String(match.1)
        }
        s = s.replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: "")
        guard let value = Int(s), value > 0 else { return nil }
        return negative ? -value : value
    }

    private static func percent(in line: String) -> Int? {
        guard let match = line.firstMatch(of: /(\d{1,2})\s*%/) else { return nil }
        return Int(match.1)
    }

    // MARK: - Rate & basis resolution

    /// Fills in percentages from amounts when labels lacked them, and works
    /// out the tax basis by testing which base reproduces the printed tax.
    private static func resolveRates(
        into result: inout ParsedReceipt,
        taxAmount: Int?,
        serviceAmount: Int?
    ) {
        let subtotal = result.printedSubtotal
            ?? (result.items.isEmpty ? nil : result.items.reduce(0) { $0 + ($1.price ?? 0) * $1.qty })

        if result.servicePercent == nil,
           let subtotal, subtotal > 0, let serviceAmount,
           let p = matchingPercent(amount: serviceAmount, base: subtotal) {
            result.servicePercent = p
        }

        guard let subtotal, subtotal > 0, let taxAmount else { return }
        let serviceBase = serviceAmount.map { subtotal + $0 }

        if let p = result.taxPercent {
            // Label gave the rate; amounts decide the base.
            if let serviceBase, serviceAmount ?? 0 > 0, matches(amount: taxAmount, base: serviceBase, percent: p) {
                result.taxBasis = .subtotalPlusService
            } else if matches(amount: taxAmount, base: subtotal, percent: p), serviceAmount ?? 0 > 0 {
                result.taxBasis = .subtotal
            }
            // No service charge → the two bases coincide; leave basis nil.
        } else {
            // No labeled rate: try subtotal+service first (the common format).
            if let serviceBase, serviceAmount ?? 0 > 0,
               let p = matchingPercent(amount: taxAmount, base: serviceBase) {
                result.taxPercent = p
                result.taxBasis = .subtotalPlusService
            } else if let p = matchingPercent(amount: taxAmount, base: subtotal) {
                result.taxPercent = p
                result.taxBasis = (serviceAmount ?? 0) > 0 ? .subtotal : nil
            }
        }
    }

    /// The whole-percent rate that reproduces `amount` from `base` within
    /// rounding tolerance, if one exists (1...25%).
    private static func matchingPercent(amount: Int, base: Int) -> Int? {
        guard base > 0, amount > 0 else { return nil }
        let p = Int((Double(amount) * 100 / Double(base)).rounded())
        guard (1...25).contains(p), matches(amount: amount, base: base, percent: p) else { return nil }
        return p
    }

    private static func matches(amount: Int, base: Int, percent: Int) -> Bool {
        abs(base * percent / 100 - amount) <= 2
    }

    // MARK: - Keywords

    private static func contains(_ lowered: String, any keywords: [String]) -> Bool {
        keywords.contains { lowered.contains($0) }
    }

    private static let subtotalKeywords = ["subtotal", "sub total", "sub-total", "sub ttl"]
    private static let taxKeywords = ["pb1", "pb 1", "pajak", "ppn", "tax"]
    private static let serviceKeywords = ["service", "svc", "layanan", "s.charge"]
    private static let discountKeywords = ["disc", "diskon", "potongan", "promo", "voucher"]
    private static let totalKeywords = ["total", "jumlah", "amount due"]
    private static let ignoreKeywords = [
        "cash", "tunai", "kembali", "kembalian", "change", "qris", "debit",
        "credit", "kartu", "npwp", "terima kasih", "thank you", "sampai jumpa",
        "kasir", "cashier", "meja", "pax", "tanggal", "order", "struk", "receipt",
        "no ", "no.", "tel", "wifi", "follow", "instagram",
    ]
}
