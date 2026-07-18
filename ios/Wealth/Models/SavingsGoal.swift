import Foundation
import SwiftData

/// A named target the user is saving toward (vacation, car down payment,
/// house fund). The paycheck planner allocates toward unfinished goals and
/// the Dashboard shows progress.
@Model
final class SavingsGoal {
    var id: UUID
    var name: String
    var targetAmount: Decimal
    var savedAmount: Decimal
    var targetDate: Date?
    var createdAt: Date

    init(name: String, targetAmount: Decimal, savedAmount: Decimal = 0, targetDate: Date? = nil) {
        self.id = UUID()
        self.name = name
        self.targetAmount = targetAmount
        self.savedAmount = savedAmount
        self.targetDate = targetDate
        self.createdAt = .now
    }

    var remaining: Decimal { max(0, targetAmount - savedAmount) }
    var isComplete: Bool { savedAmount >= targetAmount }

    var progressFraction: Double {
        guard targetAmount > 0 else { return 0 }
        return min(1, ((savedAmount / targetAmount) as NSDecimalNumber).doubleValue)
    }

    /// Monthly amount needed to hit the target date, if one is set.
    func monthlyNeeded(asOf now: Date = .now) -> Decimal? {
        guard let targetDate, targetDate > now, remaining > 0 else { return nil }
        let months = max(1, Calendar.current.dateComponents([.month], from: now, to: targetDate).month ?? 1)
        return remaining / Decimal(months)
    }
}
