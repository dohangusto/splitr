import Foundation

/// A receipt line as edited in the bill form. The parser emits one draft
/// per claimable unit (qty already exploded: a "2x" receipt line becomes
/// two drafts of qty 1); manual entry may still use qty > 1, which the
/// form explodes into individual `BillItem`s on save.
///
/// Produced by hand in manual entry, or by `ReceiptParser` from OCR — in
/// which case low-confidence fields carry `needsReview` so the mandatory
/// review form can flag them, and `sourceBox`/`confidence` let the form
/// highlight the row's region on the photo and direct attention to
/// uncertain rows.
public struct DraftItem: Identifiable, Sendable, Hashable {
    public let id: UUID
    public var name: String
    /// Whole rupiah; nil until entered. Never floating point.
    public var price: Int?
    public var qty: Int
    /// Parser was unsure (e.g. total not divisible by qty); the review form
    /// flags this row until the user edits it.
    public var needsReview: Bool
    /// Where the source line sits in the receipt photo (normalized,
    /// top-left origin); nil for manually entered rows.
    public var sourceBox: NormalizedRect?
    /// OCR confidence 0...1 of the source line; nil for manual rows.
    public var confidence: Double?

    public init(
        id: UUID = UUID(),
        name: String = "",
        price: Int? = nil,
        qty: Int = 1,
        needsReview: Bool = false,
        sourceBox: NormalizedRect? = nil,
        confidence: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.price = price
        self.qty = qty
        self.needsReview = needsReview
        self.sourceBox = sourceBox
        self.confidence = confidence
    }
}
