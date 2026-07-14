/// An exact rational number, used for claim portions and settlement math.
///
/// Money in splitr is always `Int` rupiah; `Fraction` exists so intermediate
/// values (a third of an item, a proportional tax share) stay exact until the
/// final whole-rupiah rounding step. Never use floating point for money.
public struct Fraction: Sendable, Hashable, Comparable, CustomStringConvertible {
    /// Normalized: `denominator` is always positive and `gcd(|numerator|, denominator) == 1`.
    public let numerator: Int
    public let denominator: Int

    public init(_ numerator: Int, _ denominator: Int) {
        precondition(denominator != 0, "Fraction denominator must not be zero")
        var n = numerator
        var d = denominator
        if d < 0 {
            n = -n
            d = -d
        }
        let g = Self.gcd(abs(n), d)
        self.numerator = n / g
        self.denominator = d / g
    }

    public init(_ value: Int) {
        self.init(value, 1)
    }

    public static let zero = Fraction(0)
    public static let one = Fraction(1)

    /// Largest integer less than or equal to the exact value.
    public var flooredValue: Int {
        let q = numerator / denominator
        let r = numerator % denominator
        return r < 0 ? q - 1 : q
    }

    /// Nearest integer, with halves rounding up (standard receipt rounding).
    public var roundedHalfUpValue: Int {
        Fraction(2 * numerator + denominator, 2 * denominator).flooredValue
    }

    public var isWhole: Bool { denominator == 1 }

    public var description: String {
        isWhole ? "\(numerator)" : "\(numerator)/\(denominator)"
    }

    public static func + (lhs: Fraction, rhs: Fraction) -> Fraction {
        Fraction(
            lhs.numerator * rhs.denominator + rhs.numerator * lhs.denominator,
            lhs.denominator * rhs.denominator
        )
    }

    public static func - (lhs: Fraction, rhs: Fraction) -> Fraction {
        Fraction(
            lhs.numerator * rhs.denominator - rhs.numerator * lhs.denominator,
            lhs.denominator * rhs.denominator
        )
    }

    public static func * (lhs: Fraction, rhs: Fraction) -> Fraction {
        Fraction(lhs.numerator * rhs.numerator, lhs.denominator * rhs.denominator)
    }

    public static func * (lhs: Fraction, rhs: Int) -> Fraction {
        Fraction(lhs.numerator * rhs, lhs.denominator)
    }

    public static func / (lhs: Fraction, rhs: Fraction) -> Fraction {
        precondition(rhs.numerator != 0, "Division by zero fraction")
        return Fraction(lhs.numerator * rhs.denominator, lhs.denominator * rhs.numerator)
    }

    public static func += (lhs: inout Fraction, rhs: Fraction) {
        lhs = lhs + rhs
    }

    public static func < (lhs: Fraction, rhs: Fraction) -> Bool {
        // Denominators are always positive, so cross-multiplication preserves order.
        lhs.numerator * rhs.denominator < rhs.numerator * lhs.denominator
    }

    private static func gcd(_ a: Int, _ b: Int) -> Int {
        var a = a
        var b = b
        while b != 0 {
            (a, b) = (b, a % b)
        }
        return a
    }
}

extension Fraction: Codable {
    private enum CodingKeys: String, CodingKey {
        case numerator, denominator
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let n = try container.decode(Int.self, forKey: .numerator)
        let d = try container.decode(Int.self, forKey: .denominator)
        guard d != 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: .denominator,
                in: container,
                debugDescription: "Fraction denominator must not be zero"
            )
        }
        self.init(n, d)
    }
}
