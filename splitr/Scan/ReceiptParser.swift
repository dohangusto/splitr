import Foundation
import SplitBillCore

/// Result of parsing recognized receipt text. Everything is best-effort:
/// nil means "not detected — let the user fill it in on the review form".
struct ParsedReceipt {
    var merchantName: String?
    var items: [DraftItem] = []
    /// Detected PB1 percentage (e.g. 10).
    var taxPercent: Int?
    /// Detected service charge percentage (e.g. 5).
    var servicePercent: Int?
    /// Only set when the amounts prove which base the tax was computed on;
    /// nil when there is no service charge to disambiguate.
    var taxBasis: TaxBasis?
    /// The receipt's printed subtotal, when found (verification aid).
    var printedSubtotal: Int?
    /// Content lines the parser could not turn into items — surfaced to the
    /// user for manual entry, never dropped silently.
    var unparsedLines: [String] = []
}

/// Pure, hardware-free receipt text parser for Indonesian receipts.
/// Input is recognized text lines (top to bottom); no camera, no Vision.
///
/// Handles: `Rp` prefixes, dot/comma thousand separators, trailing ",00"
/// decimals, `2x` / `x2` / `2 @unit` quantity markers, abbreviated names,
/// discount lines (excluded from items, surfaced), and PB1/service/subtotal
/// detection including which base the tax was computed on.
enum ReceiptParser {

    static func parse(text: String) -> ParsedReceipt {
        parse(lines: text.components(separatedBy: .newlines))
    }

    static func parse(lines: [String]) -> ParsedReceipt {
        var result = ParsedReceipt()
        var taxAmount: Int?
        var serviceAmount: Int?
        var sawItem = false
        var sawTotal = false

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
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
                sawTotal = true
                continue
            }
            if contains(lowered, any: Self.ignoreKeywords) {
                continue
            }

            // Item lines: name + trailing amount.
            if !sawTotal, let money = trailingMoney(in: line) {
                if money.value < 0 {
                    result.unparsedLines.append(line) // unlabeled discount
                } else if let item = parseItem(line: line, money: money) {
                    result.items.append(item)
                    sawItem = true
                } else {
                    result.unparsedLines.append(line)
                }
                continue
            }

            // Text without an amount.
            if !sawItem && !sawTotal {
                // Header block: first line is the merchant, the rest
                // (address, phone, date) is noise.
                if result.merchantName == nil {
                    result.merchantName = line
                }
            } else if !sawTotal {
                result.unparsedLines.append(line) // likely an item OCR missed the price of
            }
            // After the total line, footer text is ignorable.
        }

        resolveRates(
            into: &result,
            taxAmount: taxAmount,
            serviceAmount: serviceAmount
        )
        return result
    }

    // MARK: - Item lines

    private static func parseItem(
        line: String,
        money: (value: Int, range: Range<String.Index>)
    ) -> DraftItem? {
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

        name = name
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".…-:*"))
            .trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, qty >= 1 else { return nil }
        return DraftItem(name: name, price: unitPrice, qty: qty, needsReview: needsReview)
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
    static func trailingMoney(in line: String) -> (value: Int, range: Range<String.Index>)? {
        let pattern = /(?:Rp\.?\s*|IDR\s*)?(-?\(?\d{1,3}(?:[.,]\d{3})+(?:[.,]\d{2})?\)?|-?\(?\d{4,}\)?)\s*$/
        guard let match = line.firstMatch(of: pattern),
              let value = moneyValue(String(match.1)) else { return nil }
        return (value, match.range)
    }

    /// "55.000" → 55000, "55.000,00" → 55000, "Rp 8.000" → 8000,
    /// "(5.000)" / "-5.000" → -5000, "24000" → 24000.
    static func moneyValue(_ raw: String) -> Int? {
        var s = raw.trimmingCharacters(in: .whitespaces)
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
