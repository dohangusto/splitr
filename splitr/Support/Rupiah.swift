import Foundation

extension Int {
    /// Formats whole rupiah as "Rp 187.000" (no decimals, dot grouping).
    var rupiah: String {
        var digits = String(abs(self))
        var grouped = ""
        while digits.count > 3 {
            grouped = "." + digits.suffix(3) + grouped
            digits = String(digits.dropLast(3))
        }
        return (self < 0 ? "-Rp " : "Rp ") + digits + grouped
    }
}
