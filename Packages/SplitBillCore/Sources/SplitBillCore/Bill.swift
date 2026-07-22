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

/// What PB1 tax is computed on.
public enum TaxBasis: String, Sendable, Hashable, Codable, CaseIterable {
    /// Tax on the item subtotal only.
    case subtotal
    /// Tax on subtotal + service charge — the common Indonesian receipt
    /// format, where PB1 applies after the service charge is added.
    case subtotalPlusService
}

/// A scanned-and-reviewed receipt inside a room.
public struct Bill: Identifiable, Sendable, Hashable, Codable {
    public let id: UUID
    public var merchantName: String
    /// Opaque reference to the receipt photo (resolved by upper layers).
    public var photoReference: String?
    /// PB1 tax rate.
    public var taxRate: Rate
    public var serviceChargeRate: Rate
    /// What the tax rate applies to. Defaults to subtotal + service.
    public var taxBasis: TaxBasis
    public var items: [BillItem]
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        merchantName: String,
        photoReference: String? = nil,
        taxRate: Rate = .zero,
        serviceChargeRate: Rate = .zero,
        taxBasis: TaxBasis = .subtotalPlusService,
        items: [BillItem] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.merchantName = merchantName
        self.photoReference = photoReference
        self.taxRate = taxRate
        self.serviceChargeRate = serviceChargeRate
        self.taxBasis = taxBasis
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

    /// Service charge on the subtotal, rounded to whole rupiah like the
    /// printed receipt. Claim-independent: valid before claiming completes.
    public var serviceChargeTotal: Int {
        (serviceChargeRate.fraction * subtotal).roundedHalfUpValue
    }

    /// PB1 tax on the bill's `taxBasis`, rounded to whole rupiah.
    public var taxTotal: Int {
        let base: Int
        switch taxBasis {
        case .subtotal:
            base = subtotal
        case .subtotalPlusService:
            base = subtotal + serviceChargeTotal
        }
        return (taxRate.fraction * base).roundedHalfUpValue
    }

    /// Subtotal + tax + service — the printed receipt's bottom line.
    public var grandTotal: Int {
        subtotal + taxTotal + serviceChargeTotal
    }
}
