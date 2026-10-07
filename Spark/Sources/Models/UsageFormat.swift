import Foundation

/// A number split for display: the digits are set in Doto, the unit in SF Pro
/// (docs/design/rules.md, "Typography" and "Numbers and units").
struct NumberParts: Equatable {
    let number: String
    let unit: String
}

enum UsageFormat {
    // Dollar amounts read the same in every system locale, like `formatCost`.
    private static let enUS = Locale(identifier: "en_US")
    private static let units: [(size: Double, suffix: String)] = [(1e9, "B"), (1e6, "M"), (1e3, "K")]

    /// API cost with at most five characters of digits, so a stat tile never overflows.
    /// The tier is chosen after rounding, so 99.996 becomes "100" rather than "100.00".
    static func cost(_ dollars: Double) -> NumberParts {
        let value = dollars.isFinite ? max(dollars, 0) : 0
        if (value * 100).rounded() / 100 < 100 {
            return NumberParts(number: value.formatted(.number.precision(.fractionLength(2)).locale(enUS)), unit: "$")
        }
        if value.rounded() < 10_000 {
            return NumberParts(number: value.rounded().formatted(.number.precision(.fractionLength(0)).locale(enUS)), unit: "$")
        }
        let compactValue = compact(value)
        return NumberParts(number: compactValue.number, unit: compactValue.unit + "$")
    }

    static func tokens(_ count: Int) -> NumberParts {
        compact(Double(max(count, 0)))
    }

    static func percent(_ value: Double, locale: Locale = .current) -> String {
        let finite = value.isFinite ? value : 0
        return (finite / 100).formatted(.percent.precision(.fractionLength(0)).locale(locale))
    }

    /// One decimal in the largest unit the value reaches, promoted when rounding reaches 1000.
    private static func compact(_ value: Double) -> NumberParts {
        guard var index = units.firstIndex(where: { value >= $0.size }) else {
            return NumberParts(number: String(Int(value.rounded())), unit: "")
        }
        var scaled = (value / units[index].size * 10).rounded() / 10
        if scaled >= 1000, index > 0 {
            index -= 1
            scaled = (value / units[index].size * 10).rounded() / 10
        }
        return NumberParts(number: String(format: "%.1f", locale: enUS, scaled), unit: units[index].suffix)
    }
}
