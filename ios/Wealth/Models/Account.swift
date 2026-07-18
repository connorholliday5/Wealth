import Foundation
import SwiftData

enum AccountType: String, Codable, CaseIterable, Identifiable, Hashable {
    case checking
    case savings
    case creditCard
    case rothIRA
    case traditionalIRA
    case fourOhOneK
    case hsa
    case studentLoan
    case autoLoan
    case mortgage
    case otherLoan
    case otherAsset

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .checking: return "Checking"
        case .savings: return "Savings"
        case .creditCard: return "Credit Card"
        case .rothIRA: return "Roth IRA"
        case .traditionalIRA: return "Traditional IRA"
        case .fourOhOneK: return "401(k)"
        case .hsa: return "HSA"
        case .studentLoan: return "Student Loan"
        case .autoLoan: return "Auto Loan"
        case .mortgage: return "Mortgage"
        case .otherLoan: return "Loan"
        case .otherAsset: return "Other"
        }
    }

    var category: AccountCategory {
        switch self {
        case .checking, .savings, .otherAsset:
            return .cash
        case .creditCard:
            return .credit
        case .rothIRA, .traditionalIRA, .fourOhOneK, .hsa:
            return .investment
        case .studentLoan, .autoLoan, .mortgage, .otherLoan:
            return .loan
        }
    }

    /// Balances on these account types are owed money (liabilities), not held money.
    var isLiability: Bool {
        category == .credit || category == .loan
    }

    /// Funded through payroll rather than a checking-account transfer.
    var isWorkBenefit: Bool {
        switch self {
        case .fourOhOneK, .hsa: return true
        default: return false
        }
    }
}

enum AccountCategory: String, Codable, CaseIterable, Hashable {
    case cash
    case credit
    case investment
    case loan

    var displayName: String {
        switch self {
        case .cash: return "Cash"
        case .credit: return "Credit Cards"
        case .investment: return "Investments"
        case .loan: return "Loans"
        }
    }
}

@Model
final class Account {
    var id: UUID
    var name: String
    var institutionName: String?
    var type: AccountType
    /// Asset balance, or current amount owed for credit cards/loans. Always stored positive.
    var balance: Decimal
    var currency: String
    var isManual: Bool
    var lastSynced: Date?

    // Plaid linkage (nil for manually entered accounts)
    var plaidItemId: String?
    var plaidAccountId: String?

    // Credit card specific
    var creditLimit: Decimal?
    var apr: Double?

    // Loan specific
    var originalPrincipal: Decimal?
    var interestRate: Double?
    var minimumPayment: Decimal?
    var paymentDueDay: Int?

    // Employer-sponsored investment specific (401k / HSA)
    var employerName: String?
    var employerMatchPercent: Double?
    var employerMatchLimitPercent: Double?
    /// Contributed so far in the current calendar year, tracked manually or from payroll bills.
    var yearToDateContribution: Decimal?
    /// Calendar year the yearToDateContribution belongs to; MaintenanceEngine
    /// resets the amount when a new year starts.
    var contributionYear: Int?
    /// Overrides ContributionLimits.default(for:) when the IRS limit changes or doesn't apply.
    var contributionLimitOverride: Decimal?

    @Relationship(deleteRule: .cascade, inverse: \Transaction.account)
    var transactions: [Transaction] = []

    /// Bills that pay this account down. Nullify on delete so removing an
    /// account can never leave a bill pointing at a dangling reference.
    @Relationship(deleteRule: .nullify, inverse: \Bill.linkedAccount)
    var linkedBills: [Bill] = []

    init(
        name: String,
        type: AccountType,
        balance: Decimal,
        currency: String = "USD",
        isManual: Bool = true,
        institutionName: String? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.type = type
        self.balance = balance
        self.currency = currency
        self.isManual = isManual
        self.institutionName = institutionName
    }

    /// Contribution toward (or against) net worth: liabilities subtract.
    var netWorthContribution: Decimal {
        type.isLiability ? -balance : balance
    }
}
