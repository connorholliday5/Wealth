import Foundation

extension Decimal {
    var currencyString: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: self as NSDecimalNumber) ?? "$0.00"
    }

    /// Parses user-typed amounts respecting the device locale (so "1.234,56"
    /// works on a European keyboard), falling back to plain parsing.
    init?(userInput: String) {
        let trimmed = userInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let localized = Decimal(string: trimmed, locale: .current), localized.isFinite {
            self = localized
        } else if let plain = Decimal(string: trimmed), plain.isFinite {
            self = plain
        } else {
            return nil
        }
    }
}

/// "3 yr 2 mo", "8 mo", "now" — for payoff durations.
func monthsDurationString(_ months: Int) -> String {
    if months <= 0 { return "now" }
    let years = months / 12
    let remainder = months % 12
    if years == 0 { return "\(months) mo" }
    if remainder == 0 { return years == 1 ? "1 yr" : "\(years) yr" }
    return "\(years) yr \(remainder) mo"
}

extension Date {
    var dayCountdownString: String {
        let days = Calendar.current.dateComponents([.day], from: .now, to: self).day ?? 0
        if days < 0 { return "Past due" }
        if days == 0 { return "Due today" }
        if days == 1 { return "Due tomorrow" }
        return "Due in \(days) days"
    }
}
