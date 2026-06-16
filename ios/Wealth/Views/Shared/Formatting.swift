import Foundation

extension Decimal {
    var currencyString: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: self as NSDecimalNumber) ?? "$0.00"
    }
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
