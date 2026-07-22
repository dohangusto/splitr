import Foundation

/// One claimable unit of a receipt line. Quantity explosion happens upstream
/// (at parse/edit time): a "2x Es Teh" receipt line becomes two `BillItem`s.
public struct BillItem: Identifiable, Sendable, Hashable, Codable {
    public let id: UUID
    public var name: String
    /// Whole rupiah. Money is never floating point.
    public var unitPrice: Int
    public var claimState: ClaimState

    public init(
        id: UUID = UUID(),
        name: String,
        unitPrice: Int,
        claimState: ClaimState = .unclaimed
    ) {
        precondition(unitPrice >= 0, "unitPrice must not be negative")
        self.id = id
        self.name = name
        self.unitPrice = unitPrice
        self.claimState = claimState
    }
}

/// A scanned-and-reviewed receipt inside a room.
///
/// Tax (PB1), service charge, and discount are stored as the **exact whole-
/// rupiah amounts printed on the receipt** — not percentages. Receipts print
/// these lines directly, OCR reads them directly, and the host edits them
/// directly, so there is no rate/rounding step to get wrong. Discount is a
/// credit that reduces the total.
public struct Bill: Identifiable, Sendable, Hashable, Codable {
    public let id: UUID
    public var merchantName: String
    /// Opaque reference to the receipt photo (resolved by upper layers).
    public var photoReference: String?
    /// PB1 tax, in whole rupiah. Never negative.
    public var tax: Int
    /// Service charge, in whole rupiah. Never negative.
    public var serviceCharge: Int
    /// Discount / promo credit, in whole rupiah, subtracted from the total.
    public var discount: Int
    public var items: [BillItem]
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        merchantName: String,
        photoReference: String? = nil,
        tax: Int = 0,
        serviceCharge: Int = 0,
        discount: Int = 0,
        items: [BillItem] = [],
        createdAt: Date = Date()
    ) {
        precondition(tax >= 0, "tax must not be negative")
        precondition(serviceCharge >= 0, "serviceCharge must not be negative")
        precondition(discount >= 0, "discount must not be negative")
        self.id = id
        self.merchantName = merchantName
        self.photoReference = photoReference
        self.tax = tax
        self.serviceCharge = serviceCharge
        self.discount = discount
        self.items = items
        self.createdAt = createdAt
    }

    /// Sum of all item unit prices, in whole rupiah.
    public var subtotal: Int {
        items.reduce(0) { $0 + $1.unitPrice }
    }

    public func item(withID id: UUID) -> BillItem? {
        items.first { $0.id == id }
    }

    /// Service charge total, in whole rupiah (the stored amount).
    public var serviceChargeTotal: Int { serviceCharge }

    /// PB1 tax total, in whole rupiah (the stored amount).
    public var taxTotal: Int { tax }

    /// Discount total, in whole rupiah (the stored amount).
    public var discountTotal: Int { discount }

    /// Subtotal + tax + service − discount — the printed receipt's bottom line.
    public var grandTotal: Int {
        subtotal + tax + serviceCharge - discount
    }
}
