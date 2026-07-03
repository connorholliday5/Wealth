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

    var occurrencesPerYear: Double {
        switch self {
        case .weekly: return 52
        case .biweekly: return 26
        case .semimonthly: return 24
        case .monthly: return 12
        case .quarterly: return 4
        case .annual: return 1
        }
    }

    /// The next occurrence after `date` for this cadence. Semimonthly is
    /// approximated as 15 days since we don't store two anchor days.
    func nextDate(after date: Date) -> Date {
        let calendar = Calendar.current
        switch self {
        case .weekly: return calendar.date(byAdding: .day, value: 7, to: date) ?? date
        case .biweekly: return calendar.date(byAdding: .day, value: 14, to: date) ?? date
        case .semimonthly: return calendar.date(byAdding: .day, value: 15, to: date) ?? date
        case .monthly: return calendar.date(byAdding: .month, value: 1, to: date) ?? date
        case .quarterly: return calendar.date(byAdding: .month, value: 3, to: date) ?? date
        case .annual: return calendar.date(byAdding: .year, value: 1, to: date) ?? date
        }
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
    /// Day of month (1-31) the bill is due; for biweekly/weekly bills this anchors the first due date.
    var nextDueDate: Date
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
        self.autopay = autopay
        self.isPayrollDeduction = isPayrollDeduction
        self.linkedAccount = linkedAccount
    }

    var monthlyEquivalent: Decimal {
        amount * Decimal(frequency.occurrencesPerYear / 12)
    }

    /// Rolls the due date forward past any missed occurrences, keeping "due
    /// today" intact (only dates before the start of today are considered
    /// missed). Returns true if the date moved.
    @discardableResult
    func advancePastDue(asOf now: Date = .now) -> Bool {
        let startOfToday = Calendar.current.startOfDay(for: now)
        var advanced = false
        var safety = 0
        while nextDueDate < startOfToday && safety < 1000 {
            nextDueDate = frequency.nextDate(after: nextDueDate)
            advanced = true
            safety += 1
        }
        return advanced
    }

    /// Marks the current occurrence paid: advances the due date one cycle and,
    /// if this payment pays down a linked debt, reduces that balance.
    func markPaid() {
        nextDueDate = frequency.nextDate(after: nextDueDate)
        if let account = linkedAccount, account.type.isLiability {
            account.balance = max(0, account.balance - amount)
        }
    }
}
