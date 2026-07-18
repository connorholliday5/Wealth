import Foundation
import SwiftData

enum BillFrequency: String, Codable, CaseIterable, Identifiable, Hashable {
    case weekly
    case biweekly
    /// Twice a month on fixed days, e.g. payroll-deducted benefits.
    case semimonthly
    case monthly
    case quarterly
    case annual

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .weekly: return "Weekly"
        case .biweekly: return "Every 2 weeks"
        case .semimonthly: return "Twice a month"
        case .monthly: return "Monthly"
        case .quarterly: return "Quarterly"
        case .annual: return "Annual"
        }
    }

    var occurrencesPerYear: Int {
        switch self {
        case .weekly: return 52
        case .biweekly: return 26
        case .semimonthly: return 24
        case .monthly: return 12
        case .quarterly: return 4
        case .annual: return 1
        }
    }

    /// The next occurrence after `date` for this cadence. Month-based cadences
    /// preserve `anchorDay` (the original due day-of-month) so a bill due on
    /// the 31st doesn't permanently drift earlier after passing February —
    /// it clamps to short months (Feb 28) but snaps back (Mar 31). Semimonthly
    /// is approximated as 15 days since we don't store two anchor days.
    func nextDate(after date: Date, anchorDay: Int? = nil) -> Date {
        let calendar = Calendar.current
        switch self {
        case .weekly: return calendar.date(byAdding: .day, value: 7, to: date) ?? date
        case .biweekly: return calendar.date(byAdding: .day, value: 14, to: date) ?? date
        case .semimonthly: return calendar.date(byAdding: .day, value: 15, to: date) ?? date
        case .monthly: return Self.addMonthsPreservingDay(1, to: date, anchorDay: anchorDay)
        case .quarterly: return Self.addMonthsPreservingDay(3, to: date, anchorDay: anchorDay)
        case .annual: return Self.addMonthsPreservingDay(12, to: date, anchorDay: anchorDay)
        }
    }

    private static func addMonthsPreservingDay(_ months: Int, to date: Date, anchorDay: Int?) -> Date {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        let desiredDay = anchorDay ?? components.day ?? 1
        components.day = 1
        guard let monthStart = calendar.date(from: components),
              let targetStart = calendar.date(byAdding: .month, value: months, to: monthStart),
              let dayRange = calendar.range(of: .day, in: .month, for: targetStart) else {
            return calendar.date(byAdding: .month, value: months, to: date) ?? date
        }
        var target = calendar.dateComponents([.year, .month], from: targetStart)
        target.day = min(max(desiredDay, 1), dayRange.count)
        return calendar.date(from: target) ?? date
    }
}

enum BillKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case rent
    case utility
    case subscription
    case insurance
    case loanPayment
    case creditCardPayment
    /// Payroll-deducted employer benefit premium (health/dental/vision), distinct from
    /// 401k/HSA contributions which live on the Account itself.
    case workBenefitPremium
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .rent: return "Rent/Mortgage"
        case .utility: return "Utility"
        case .subscription: return "Subscription"
        case .insurance: return "Insurance"
        case .loanPayment: return "Loan Payment"
        case .creditCardPayment: return "Credit Card Payment"
        case .workBenefitPremium: return "Work Benefit"
        case .other: return "Other"
        }
    }
}

@Model
final class Bill {
    var id: UUID
    var name: String
    var amount: Decimal
    var kind: BillKind
    var frequency: BillFrequency
    var nextDueDate: Date
    /// The original due day-of-month (1-31), so month-based cadences snap back
    /// to the right day after short months instead of drifting. nil on rows
    /// created before this field existed — those fall back to the current day.
    var dueDayAnchor: Int?
    var autopay: Bool
    var isPayrollDeduction: Bool
    /// The loan or credit card this payment pays down, if any.
    var linkedAccount: Account?

    init(
        name: String,
        amount: Decimal,
        kind: BillKind,
        frequency: BillFrequency,
        nextDueDate: Date,
        autopay: Bool = false,
        isPayrollDeduction: Bool = false,
        linkedAccount: Account? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.amount = amount
        self.kind = kind
        self.frequency = frequency
        self.nextDueDate = nextDueDate
        self.dueDayAnchor = Calendar.current.component(.day, from: nextDueDate)
        self.autopay = autopay
        self.isPayrollDeduction = isPayrollDeduction
        self.linkedAccount = linkedAccount
    }

    var monthlyEquivalent: Decimal {
        // Integer occurrences / exact division — no Double detour, no drift.
        amount * Decimal(frequency.occurrencesPerYear) / Decimal(12)
    }

    /// Rolls the due date forward past any missed occurrences, keeping "due
    /// today" intact (only dates before the start of today are considered
    /// missed). Returns how many occurrences were skipped (0 = date unchanged).
    @discardableResult
    func advancePastDue(asOf now: Date = .now) -> Int {
        let startOfToday = Calendar.current.startOfDay(for: now)
        var skipped = 0
        while nextDueDate < startOfToday && skipped < 1000 {
            nextDueDate = frequency.nextDate(after: nextDueDate, anchorDay: dueDayAnchor)
            skipped += 1
        }
        return skipped
    }

    /// Marks the current occurrence paid: advances the due date one cycle and,
    /// if this payment pays down a linked debt, reduces that balance.
    func markPaid() {
        nextDueDate = frequency.nextDate(after: nextDueDate, anchorDay: dueDayAnchor)
        if let account = linkedAccount, account.type.isLiability {
            account.balance = max(0, account.balance - amount)
        }
    }
}
