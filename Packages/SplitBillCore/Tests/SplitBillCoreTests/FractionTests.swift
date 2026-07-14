import Testing
@testable import SplitBillCore

@Suite("Fraction")
struct FractionTests {
    @Test("Fractions normalize sign and reduce to lowest terms")
    func normalization() {
        #expect(Fraction(2, 4) == Fraction(1, 2))
        #expect(Fraction(-1, -2) == Fraction(1, 2))
        #expect(Fraction(1, -2) == Fraction(-1, 2))
        #expect(Fraction(0, 7) == .zero)
    }

    @Test("Equal splits sum back to exactly one")
    func thirdsSumToOne() {
        let third = Fraction(1, 3)
        #expect(third + third + third == .one)
    }

    @Test("Arithmetic is exact")
    func arithmetic() {
        #expect(Fraction(1, 2) + Fraction(1, 3) == Fraction(5, 6))
        #expect(Fraction(1, 2) - Fraction(1, 3) == Fraction(1, 6))
        #expect(Fraction(2, 3) * Fraction(3, 4) == Fraction(1, 2))
        #expect(Fraction(1, 3) * 25_000 == Fraction(25_000, 3))
        #expect(Fraction(1, 2) / Fraction(1, 4) == Fraction(2))
    }

    @Test("Floor and half-up rounding to whole rupiah")
    func rounding() {
        #expect(Fraction(25_000, 3).flooredValue == 8_333)
        #expect(Fraction(25_000, 3).roundedHalfUpValue == 8_333)
        #expect(Fraction(50_000, 3).roundedHalfUpValue == 16_667)
        #expect(Fraction(1, 2).roundedHalfUpValue == 1)
        #expect(Fraction(-1, 2).flooredValue == -1)
        #expect(Fraction(7).flooredValue == 7)
    }

    @Test("Comparison works across denominators")
    func comparison() {
        #expect(Fraction(1, 3) < Fraction(1, 2))
        #expect(Fraction(2, 6) == Fraction(1, 3))
        #expect(Fraction(1, 100) > .zero)
    }
}
