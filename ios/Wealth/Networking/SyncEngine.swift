import Foundation
import SwiftData

/// Pulls fresh data from the Wealth server into the local SwiftData store for
/// every Plaid-linked account: current balances, credit-card APRs / loan terms,
/// and the transaction feed (incremental — the server remembers a cursor per
/// institution, so each sync only transfers what changed).
///
/// Triggered from pull-to-refresh and automatically on app open (throttled).
/// Manual accounts are never touched.
@MainActor
final class SyncEngine: ObservableObject {
    static let shared = SyncEngine()
    private init() {
        lastSyncedAt = UserDefaults.standard.object(forKey: "lastSyncedAt") as? Date
    }

    @Published var isSyncing = false
    @Published var lastSyncError: String?
    @Published var lastSyncedAt: Date? {
        didSet { UserDefaults.standard.set(lastSyncedAt, forKey: "lastSyncedAt") }
    }

    private static let autoSyncInterval: TimeInterval = 15 * 60

    /// Syncs on app open, but at most every 15 minutes.
    func autoSyncIfStale(context: ModelContext) async {
        if let last = lastSyncedAt, Date.now.timeIntervalSince(last) < Self.autoSyncInterval {
            return
        }
        await syncAll(context: context)
    }

    func syncAll(context: ModelContext) async {
        guard !isSyncing else { return }

        let allAccounts = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        let linkedAccounts = allAccounts.filter { $0.plaidItemId != nil && $0.plaidAccountId != nil }
        guard !linkedAccounts.isEmpty else { return }

        isSyncing = true
        defer { isSyncing = false }

        var accountsByPlaidId: [String: Account] = [:]
        for account in linkedAccounts {
            accountsByPlaidId[account.plaidAccountId!] = account
        }

        do {
            try await syncBalances(accountsByPlaidId: accountsByPlaidId)

            let itemIds = Set(linkedAccounts.compactMap(\.plaidItemId))
            for itemId in itemIds {
                // Liability details are best-effort: not every institution or
                // account type supports them, and that shouldn't fail the sync.
                if let liabilities = try? await PlaidAPIClient.fetchLiabilities(itemId: itemId) {
                    Self.apply(liabilities: liabilities, accountsByPlaidId: accountsByPlaidId)
                }
                try await syncTransactions(itemId: itemId, accountsByPlaidId: accountsByPlaidId, context: context)
            }

            let now = Date.now
            for account in linkedAccounts { account.lastSynced = now }
            try? context.save()

            lastSyncedAt = now
            lastSyncError = nil
        } catch {
            lastSyncError = error.localizedDescription
        }
    }

    // MARK: - Balances

    private func syncBalances(accountsByPlaidId: [String: Account]) async throws {
        let items = try await PlaidAPIClient.fetchAccounts()
        for item in items {
            for plaidAccount in item.accounts {
                guard let local = accountsByPlaidId[plaidAccount.accountId],
                      let current = plaidAccount.balances.current else { continue }
                local.balance = Decimal(current)
            }
        }
    }

    // MARK: - Liabilities (APRs, loan terms)

    static func apply(liabilities: PlaidLiabilities, accountsByPlaidId: [String: Account]) {
        for card in liabilities.credit ?? [] {
            guard let id = card.accountId, let account = accountsByPlaidId[id] else { continue }
            // Prefer the purchase APR; fall back to whatever is listed first.
            let aprs = card.aprs ?? []
            let purchase = aprs.first { $0.aprType == "purchase_apr" } ?? aprs.first
            if let apr = purchase?.aprPercentage { account.apr = apr }
            if let minimum = card.minimumPaymentAmount { account.minimumPayment = Decimal(minimum) }
        }
        for loan in liabilities.student ?? [] {
            guard let id = loan.accountId, let account = accountsByPlaidId[id] else { continue }
            if let rate = loan.interestRatePercentage { account.interestRate = rate }
            if let minimum = loan.minimumPaymentAmount { account.minimumPayment = Decimal(minimum) }
        }
        for mortgage in liabilities.mortgage ?? [] {
            guard let id = mortgage.accountId, let account = accountsByPlaidId[id] else { continue }
            if let rate = mortgage.interestRate?.percentage { account.interestRate = rate }
            if let payment = mortgage.nextMonthlyPayment { account.minimumPayment = Decimal(payment) }
        }
    }

    // MARK: - Transactions

    private func syncTransactions(
        itemId: String,
        accountsByPlaidId: [String: Account],
        context: ModelContext
    ) async throws {
        // Index existing Plaid-sourced transactions once for dedupe/update/remove.
        let existing = (try? context.fetch(
            FetchDescriptor<Transaction>(predicate: #Predicate { $0.plaidTransactionId != nil })
        )) ?? []
        var byPlaidId: [String: Transaction] = [:]
        for transaction in existing {
            if let pid = transaction.plaidTransactionId { byPlaidId[pid] = transaction }
        }

        // Fresh install (no imported transactions at all): ask the server to
        // replay full history for this institution.
        let restart = byPlaidId.isEmpty
        let sync = try await PlaidAPIClient.syncTransactions(itemId: itemId, restart: restart)

        for wire in sync.added + sync.modified {
            guard let account = accountsByPlaidId[wire.accountId] else { continue }
            let transaction = byPlaidId[wire.transactionId] ?? {
                let fresh = Transaction(
                    date: .now,
                    amount: 0,
                    merchantName: "",
                    category: .other
                )
                fresh.plaidTransactionId = wire.transactionId
                context.insert(fresh)
                byPlaidId[wire.transactionId] = fresh
                return fresh
            }()

            // Plaid: positive = money out. Local model: positive = money in.
            transaction.amount = Decimal(-wire.amount)
            transaction.date = Self.parseDate(wire.date) ?? transaction.date
            transaction.merchantName = wire.merchantName ?? wire.name ?? "Unknown"
            transaction.pending = wire.pending ?? false
            transaction.category = Self.mapCategory(
                primary: wire.personalFinanceCategory?.primary,
                detailed: wire.personalFinanceCategory?.detailed
            )
            transaction.account = account
        }

        for removed in sync.removed {
            if let transaction = byPlaidId[removed.transactionId] {
                context.delete(transaction)
                byPlaidId[removed.transactionId] = nil
            }
        }
    }

    static func parseDate(_ string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: string)
    }

    /// Maps Plaid's personal-finance-category taxonomy onto the app's
    /// SpendingCategory so synced transactions feed the insights engine.
    static func mapCategory(primary: String?, detailed: String?) -> SpendingCategory {
        switch primary {
        case "INCOME":
            return .income
        case "TRANSFER_IN", "TRANSFER_OUT":
            return .savingsTransfer
        case "LOAN_PAYMENTS":
            return .debtPayment
        case "FOOD_AND_DRINK":
            return detailed?.contains("GROCERIES") == true ? .groceries : .dining
        case "GENERAL_MERCHANDISE":
            return .shopping
        case "HOME_IMPROVEMENT":
            return .housing
        case "RENT_AND_UTILITIES":
            return detailed?.contains("RENT") == true ? .housing : .utilities
        case "MEDICAL":
            return .healthcare
        case "GENERAL_SERVICES":
            return detailed?.contains("INSURANCE") == true ? .insurance : .other
        case "TRANSPORTATION":
            return .transportation
        case "TRAVEL":
            return .entertainment
        case "ENTERTAINMENT":
            return .entertainment
        default:
            return .other
        }
    }
}
