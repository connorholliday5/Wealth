import Foundation
import SwiftData

enum SpendingCategory: String, Codable, CaseIterable, Identifiable, Hashable {
    case income
    case housing
    case utilities
    case groceries
    case dining
    case transportation
    case healthcare
    case insurance
    case subscriptions
    case shopping
    case entertainment
    case debtPayment
    case savingsTransfer
    case workBenefit
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .income: return "Income"
        case .housing: return "Housing"
        case .utilities: return "Utilities"
        case .groceries: return "Groceries"
        case .dining: return "Dining"
        case .transportation: return "Transportation"
        case .healthcare: return "Healthcare"
        case .insurance: return "Insurance"
        case .subscriptions: return "Subscriptions"
        case .shopping: return "Shopping"
        case .entertainment: return "Entertainment"
        case .debtPayment: return "Debt Payment"
        case .savingsTransfer: return "Savings/Transfer"
        case .workBenefit: return "Work Benefit"
        case .other: return "Other"
        }
    }
}

@Model
final class Transaction {
    var id: UUID
    var date: Date
    /// Positive = money in, negative = money out.
    var amount: Decimal
    var merchantName: String
    var category: SpendingCategory
    var pending: Bool
    var plaidTransactionId: String?

    var account: Account?

    init(
        date: Date,
        amount: Decimal,
        merchantName: String,
        category: SpendingCategory = .other,
        pending: Bool = false
    ) {
        self.id = UUID()
        self.date = date
        self.amount = amount
        self.merchantName = merchantName
        self.category = category
        self.pending = pending
    }
}
