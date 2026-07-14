import Foundation

/// A receipt line as edited in the bill form. Qty explodes into individual
/// claimable `BillItem` units on save (qty 3 → 3 rows).
///
/// Produced by hand in manual entry, or by `ReceiptParser` from OCR text —
/// in which case low-confidence fields carry `needsReview` so the mandatory
/// review form can flag them.
struct DraftItem: Identifiable {
    let id = UUID()
    var name = ""
    var price: Int?
    var qty = 1
    /// Parser was unsure (e.g. total not divisible by qty); the review form
    /// flags this row until the user edits it.
    var needsReview = false
}
