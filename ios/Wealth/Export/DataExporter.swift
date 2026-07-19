import Foundation
import SwiftData

/// Produces user-facing exports of everything entered into Wealth so the owner
/// of the data can get it back out — as spreadsheet-friendly CSV files or as a
/// single full-fidelity JSON backup. All files are written to the system
/// temporary directory and returned as URLs ready to hand to a share sheet.
///
/// Note on money: `Decimal` values are encoded as **strings** in the JSON
/// backup (and printed plainly in CSV) so exact cents survive the round trip —
/// encoding them as JSON numbers would route through Double and risk precision
/// loss on values that can't be represented exactly in binary floating point.
@MainActor
enum DataExporter {

    // MARK: - CSV

    /// Writes accounts.csv, transactions.csv and bills.csv to the temp directory
    /// and returns their URLs (in that order).
    static func csvExports(context: ModelContext) throws -> [URL] {
        let accounts = try context.fetch(FetchDescriptor<Account>())
        let transactions = try context.fetch(FetchDescriptor<Transaction>())
        let bills = try context.fetch(FetchDescriptor<Bill>())

        let dayFormatter = DateFormatter()
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.timeZone = TimeZone(identifier: "UTC")
        dayFormatter.dateFormat = "yyyy-MM-dd"

        // accounts.csv
        var accountRows = ["name,type,balance,institution,apr,interest_rate,minimum_payment,credit_limit"]
        for account in accounts {
            accountRows.append(csvRow([
                account.name,
                account.type.rawValue,
                decimalString(account.balance),
                account.institutionName ?? "",
                doubleString(account.apr),
                doubleString(account.interestRate),
                decimalString(account.minimumPayment),
                decimalString(account.creditLimit)
            ]))
        }

        // transactions.csv
        var transactionRows = ["date,merchant,amount,category,account,pending"]
        for transaction in transactions {
            transactionRows.append(csvRow([
                dayFormatter.string(from: transaction.date),
                transaction.merchantName,
                decimalString(transaction.amount),
                transaction.category.rawValue,
                transaction.account?.name ?? "",
                transaction.pending ? "true" : "false"
            ]))
        }

        // bills.csv
        var billRows = ["name,amount,kind,frequency,next_due,autopay,payroll_deduction,linked_account"]
        for bill in bills {
            billRows.append(csvRow([
                bill.name,
                decimalString(bill.amount),
                bill.kind.rawValue,
                bill.frequency.rawValue,
                dayFormatter.string(from: bill.nextDueDate),
                bill.autopay ? "true" : "false",
                bill.isPayrollDeduction ? "true" : "false",
                bill.linkedAccount?.name ?? ""
            ]))
        }

        let accountsURL = try write(accountRows.joined(separator: "\n"), to: "accounts.csv")
        let transactionsURL = try write(transactionRows.joined(separator: "\n"), to: "transactions.csv")
        let billsURL = try write(billRows.joined(separator: "\n"), to: "bills.csv")
        return [accountsURL, transactionsURL, billsURL]
    }

    // MARK: - JSON backup

    /// Writes a single wealth-backup.json capturing every user-entered field
    /// across accounts, transactions, bills, goals and budgets, and returns its
    /// URL.
    static func jsonBackup(context: ModelContext) throws -> URL {
        let accounts = try context.fetch(FetchDescriptor<Account>())
        let transactions = try context.fetch(FetchDescriptor<Transaction>())
        let bills = try context.fetch(FetchDescriptor<Bill>())
        let goals = try context.fetch(FetchDescriptor<SavingsGoal>())
        let budgets = try context.fetch(FetchDescriptor<Budget>())

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]

        let backup = Backup(
            exportedAt: iso.string(from: Date()),
            accounts: accounts.map { AccountDTO($0, iso: iso) },
            transactions: transactions.map { TransactionDTO($0, iso: iso) },
            bills: bills.map { BillDTO($0, iso: iso) },
            goals: goals.map { GoalDTO($0, iso: iso) },
            budgets: budgets.map { BudgetDTO($0) }
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(backup)

        let url = FileManager.default.temporaryDirectory.appending(path: "wealth-backup.json")
        try data.write(to: url, options: .atomic)
        return url
    }

    // MARK: - Codable transfer objects
    // Decimals are represented as String (see the type-level note) to preserve
    // exact cents. Optional monetary/rate fields stay optional so an absent
    // value is distinguishable from zero.

    private struct Backup: Codable {
        let exportedAt: String
        let accounts: [AccountDTO]
        let transactions: [TransactionDTO]
        let bills: [BillDTO]
        let goals: [GoalDTO]
        let budgets: [BudgetDTO]
    }

    private struct AccountDTO: Codable {
        let id: String
        let name: String
        let institutionName: String?
        let type: String
        let balance: String
        let currency: String
        let isManual: Bool
        let lastSynced: String?
        let plaidItemId: String?
        let plaidAccountId: String?
        let creditLimit: String?
        let apr: Double?
        let originalPrincipal: String?
        let interestRate: Double?
        let minimumPayment: String?
        let paymentDueDay: Int?
        let employerName: String?
        let employerMatchPercent: Double?
        let employerMatchLimitPercent: Double?
        let yearToDateContribution: String?
        let contributionYear: Int?
        let contributionLimitOverride: String?

        init(_ account: Account, iso: ISO8601DateFormatter) {
            id = account.id.uuidString
            name = account.name
            institutionName = account.institutionName
            type = account.type.rawValue
            balance = DataExporter.decimalString(account.balance)
            currency = account.currency
            isManual = account.isManual
            lastSynced = account.lastSynced.map { iso.string(from: $0) }
            plaidItemId = account.plaidItemId
            plaidAccountId = account.plaidAccountId
            creditLimit = DataExporter.optionalDecimalString(account.creditLimit)
            apr = account.apr
            originalPrincipal = DataExporter.optionalDecimalString(account.originalPrincipal)
            interestRate = account.interestRate
            minimumPayment = DataExporter.optionalDecimalString(account.minimumPayment)
            paymentDueDay = account.paymentDueDay
            employerName = account.employerName
            employerMatchPercent = account.employerMatchPercent
            employerMatchLimitPercent = account.employerMatchLimitPercent
            yearToDateContribution = DataExporter.optionalDecimalString(account.yearToDateContribution)
            contributionYear = account.contributionYear
            contributionLimitOverride = DataExporter.optionalDecimalString(account.contributionLimitOverride)
        }
    }

    private struct TransactionDTO: Codable {
        let id: String
        let date: String
        let amount: String
        let merchantName: String
        let category: String
        let pending: Bool
        let plaidTransactionId: String?
        let account: String?

        init(_ transaction: Transaction, iso: ISO8601DateFormatter) {
            id = transaction.id.uuidString
            date = iso.string(from: transaction.date)
            amount = DataExporter.decimalString(transaction.amount)
            merchantName = transaction.merchantName
            category = transaction.category.rawValue
            pending = transaction.pending
            plaidTransactionId = transaction.plaidTransactionId
            account = transaction.account?.name
        }
    }

    private struct BillDTO: Codable {
        let id: String
        let name: String
        let amount: String
        let kind: String
        let frequency: String
        let nextDueDate: String
        let dueDayAnchor: Int?
        let autopay: Bool
        let isPayrollDeduction: Bool
        let linkedAccount: String?

        init(_ bill: Bill, iso: ISO8601DateFormatter) {
            id = bill.id.uuidString
            name = bill.name
            amount = DataExporter.decimalString(bill.amount)
            kind = bill.kind.rawValue
            frequency = bill.frequency.rawValue
            nextDueDate = iso.string(from: bill.nextDueDate)
            dueDayAnchor = bill.dueDayAnchor
            autopay = bill.autopay
            isPayrollDeduction = bill.isPayrollDeduction
            linkedAccount = bill.linkedAccount?.name
        }
    }

    private struct GoalDTO: Codable {
        let id: String
        let name: String
        let targetAmount: String
        let savedAmount: String
        let targetDate: String?
        let createdAt: String

        init(_ goal: SavingsGoal, iso: ISO8601DateFormatter) {
            id = goal.id.uuidString
            name = goal.name
            targetAmount = DataExporter.decimalString(goal.targetAmount)
            savedAmount = DataExporter.decimalString(goal.savedAmount)
            targetDate = goal.targetDate.map { iso.string(from: $0) }
            createdAt = iso.string(from: goal.createdAt)
        }
    }

    private struct BudgetDTO: Codable {
        let id: String
        let category: String
        let monthlyLimit: String

        init(_ budget: Budget) {
            id = budget.id.uuidString
            category = budget.category.rawValue
            monthlyLimit = DataExporter.decimalString(budget.monthlyLimit)
        }
    }

    // MARK: - Formatting helpers

    /// Plain, locale-independent decimal string (e.g. "1234.56").
    fileprivate static func decimalString(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }

    fileprivate static func decimalString(_ value: Decimal?) -> String {
        guard let value else { return "" }
        return decimalString(value)
    }

    /// Nil-preserving variant for JSON (empty CSV cells use `decimalString`).
    fileprivate static func optionalDecimalString(_ value: Decimal?) -> String? {
        guard let value else { return nil }
        return decimalString(value)
    }

    private static func doubleString(_ value: Double?) -> String {
        guard let value else { return "" }
        return String(value)
    }

    // MARK: - CSV escaping / IO

    /// Joins fields into a CSV row, quoting any field that contains a comma,
    /// quote or newline and doubling inner quotes per RFC 4180.
    private static func csvRow(_ fields: [String]) -> String {
        fields.map(csvField).joined(separator: ",")
    }

    private static func csvField(_ raw: String) -> String {
        if raw.contains(",") || raw.contains("\"") || raw.contains("\n") || raw.contains("\r") {
            let escaped = raw.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return raw
    }

    private static func write(_ contents: String, to fileName: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: fileName)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
