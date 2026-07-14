/// A percentage rate (tax, service charge) stored exactly as basis points.
/// 1 basis point = 0.01%, so `Rate(basisPoints: 1_000)` is 10%.
public struct Rate: Sendable, Hashable, Codable {
    public var basisPoints: Int

    public init(basisPoints: Int) {
        precondition(basisPoints >= 0, "Rate must not be negative")
        self.basisPoints = basisPoints
    }

    public static func percent(_ percent: Int) -> Rate {
        Rate(basisPoints: percent * 100)
    }

    public static let zero = Rate(basisPoints: 0)

    public var fraction: Fraction {
        Fraction(basisPoints, 10_000)
    }
}
