import Foundation
import SwiftData

/// A monthly spending cap for one category. Spending is measured against the
/// current calendar month's transactions.
@Model
final class Budget {
    var id: UUID
    var category: SpendingCategory
    var monthlyLimit: Decimal

    init(category: SpendingCategory, monthlyLimit: Decimal) {
        self.id = UUID()
        self.category = category
        self.monthlyLimit = monthlyLimit
    }
}

/// Pure helpers for budget math — kept off the @Model so they're testable.
enum BudgetMath {
    /// Month-to-date spending per category (positive numbers, spending only).
    static func monthToDateSpending(transactions: [Transaction], asOf now: Date = .now) -> [SpendingCategory: Decimal] {
        let calendar = Calendar.current
        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) else {
            return [:]
        }
        let recent = transactions.filter {
            $0.date >= monthStart && $0.amount < 0 && !InsightsEngine.nonSpendingCategories.contains($0.category)
        }
        return Dictionary(grouping: recent, by: \.category)
            .mapValues { $0.reduce(Decimal(0)) { $0 + (-$1.amount) } }
    }

    /// Fraction of the month elapsed (0...1), for "on pace" comparisons.
    static func monthElapsedFraction(asOf now: Date = .now) -> Double {
        let calendar = Calendar.current
        guard let range = calendar.range(of: .day, in: .month, for: now) else { return 0 }
        let day = calendar.component(.day, from: now)
        return Double(day) / Double(range.count)
    }
}
