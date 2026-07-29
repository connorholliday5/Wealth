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
    /// Banks whose connection broke (Plaid ITEM_LOGIN_REQUIRED) and need the
    /// user to reconnect via update-mode Plaid Link. Rebuilt on every balance
    /// sync, so an item clears itself once its balances fetch again.
    @Published var itemsNeedingRelink: [(itemId: String, institutionName: String?)] = []
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
        isSyncing = true
        defer { isSyncing = false }

        var failures: [String] = []

        // Balances first — and this ALSO creates local accounts for anything
        // the server has linked that the app doesn't know about yet. That makes
        // linking self-healing: if Plaid wasn't ready with account data at the
        // moment Link finished, the next sync or pull-to-refresh picks it up
        // instead of the link being silently lost.
        do {
            _ = try await fetchAndApplyAccounts(context: context)
        } catch {
            failures.append("Balances: \(error.localizedDescription)")
        }

        let allAccounts = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        let linkedAccounts = allAccounts.filter { $0.plaidItemId != nil && $0.plaidAccountId != nil }
        guard !linkedAccounts.isEmpty else {
            finish(failures: failures)
            return
        }

        var accountsByPlaidId: [String: Account] = [:]
        for account in linkedAccounts {
            accountsByPlaidId[account.plaidAccountId!] = account
        }

        // Each institution syncs independently — one bank needing re-login
        // shouldn't block the others from updating.
        let itemIds = Set(linkedAccounts.compactMap(\.plaidItemId))
        for itemId in itemIds {
            // Liability details are best-effort: not every institution or
            // account type supports them, and that shouldn't fail the sync.
            if let liabilities = try? await PlaidAPIClient.fetchLiabilities(itemId: itemId) {
                Self.apply(liabilities: liabilities, accountsByPlaidId: accountsByPlaidId)
            }
            do {
                try await syncTransactions(itemId: itemId, accountsByPlaidId: accountsByPlaidId, context: context)
            } catch {
                let name = linkedAccounts.first { $0.plaidItemId == itemId }?.institutionName ?? "One bank"
                failures.append("\(name): \(error.localizedDescription)")
            }
        }

        let now = Date.now
        for account in linkedAccounts { account.lastSynced = now }
        try? context.save()
        finish(failures: failures)
    }

    private func finish(failures: [String]) {
        if failures.isEmpty {
            lastSyncedAt = .now
            lastSyncError = nil
        } else {
            lastSyncError = failures.joined(separator: " · ")
        }
    }

    // MARK: - Accounts (import + balances)

    /// Pulls the server's linked accounts and creates local rows for any the
    /// app doesn't have yet. Returns how many were created. Non-throwing —
    /// used right after Plaid Link finishes.
    @discardableResult
    func importNewAccounts(context: ModelContext) async -> Int {
        (try? await fetchAndApplyAccounts(context: context)) ?? 0
    }

    private func fetchAndApplyAccounts(context: ModelContext) async throws -> Int {
        let (items, failures) = try await PlaidAPIClient.fetchAccounts()

        // Rebuild the relink list from this fetch. Items that fetched
        // successfully drop out (cleared); those returning ITEM_LOGIN_REQUIRED
        // surface a reconnect prompt in the UI.
        itemsNeedingRelink = failures
            .filter { $0.code == "ITEM_LOGIN_REQUIRED" }
            .map { (itemId: $0.itemId, institutionName: $0.institutionName) }

        return applyAccounts(items: items, context: context)
    }

    /// Updates balances for accounts we already have and inserts any new ones.
    /// Matching is by Plaid's account_id, so this can never duplicate an
    /// account. This is the single path that turns a Plaid link into local
    /// accounts — shared by the link flow and every sync.
    @discardableResult
    private func applyAccounts(items: [LinkedItemAccounts], context: ModelContext) -> Int {
        let existing = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        var byPlaidId: [String: Account] = [:]
        for account in existing {
            if let plaidId = account.plaidAccountId { byPlaidId[plaidId] = account }
        }

        var created = 0
        for item in items {
            for plaidAccount in item.accounts {
                if let local = byPlaidId[plaidAccount.accountId] {
                    if let current = plaidAccount.balances.current {
                        local.balance = Self.money(current)
                    }
                    if local.type == .creditCard, let limit = plaidAccount.balances.limit, limit > 0 {
                        local.creditLimit = Self.money(limit)
                    }
                } else {
                    let account = Account(
                        name: plaidAccount.name,
                        type: AccountType.from(plaidType: plaidAccount.type, subtype: plaidAccount.subtype),
                        balance: Self.money(plaidAccount.balances.current ?? 0),
                        isManual: false,
                        institutionName: item.institutionName
                    )
                    account.plaidItemId = item.itemId
                    account.plaidAccountId = plaidAccount.accountId
                    account.lastSynced = .now
                    if account.type == .creditCard, let limit = plaidAccount.balances.limit, limit > 0 {
                        account.creditLimit = Self.money(limit)
                    }
                    context.insert(account)
                    byPlaidId[plaidAccount.accountId] = account
                    created += 1
                }
            }
        }
        if created > 0 { try? context.save() }
        return created
    }

    /// Converts a JSON-decoded Double into a money Decimal by rounding to
    /// cents via string, avoiding binary-float residue like 42.500000000000004.
    static func money(_ value: Double) -> Decimal {
        Decimal(string: String(format: "%.2f", value)) ?? Decimal(value)
    }

    // MARK: - Liabilities (APRs, loan terms)

    static func apply(liabilities: PlaidLiabilities, accountsByPlaidId: [String: Account]) {
        for card in liabilities.credit ?? [] {
            guard let id = card.accountId, let account = accountsByPlaidId[id] else { continue }
            // Prefer the purchase APR; fall back to whatever is listed first.
            let aprs = card.aprs ?? []
            let purchase = aprs.first { $0.aprType == "purchase_apr" } ?? aprs.first
            if let apr = purchase?.aprPercentage { account.apr = apr }
            if let minimum = card.minimumPaymentAmount { account.minimumPayment = Self.money(minimum) }
        }
        for loan in liabilities.student ?? [] {
            guard let id = loan.accountId, let account = accountsByPlaidId[id] else { continue }
            if let rate = loan.interestRatePercentage { account.interestRate = rate }
            if let minimum = loan.minimumPaymentAmount { account.minimumPayment = Self.money(minimum) }
        }
        for mortgage in liabilities.mortgage ?? [] {
            guard let id = mortgage.accountId, let account = accountsByPlaidId[id] else { continue }
            if let rate = mortgage.interestRate?.percentage { account.interestRate = rate }
            if let payment = mortgage.nextMonthlyPayment { account.minimumPayment = Self.money(payment) }
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

        // Fresh install for THIS institution: replay its full history. Scoped
        // per item — a global "any transactions exist" check would let the
        // first-processed bank replay and silently skip history for the rest.
        let itemAccountIds = Set(
            accountsByPlaidId.values
                .filter { $0.plaidItemId == itemId }
                .compactMap(\.plaidAccountId)
        )
        let hasHistoryForItem = existing.contains { transaction in
            guard let accountPlaidId = transaction.account?.plaidAccountId else { return false }
            return itemAccountIds.contains(accountPlaidId)
        }
        let sync = try await PlaidAPIClient.syncTransactions(itemId: itemId, restart: !hasHistoryForItem)

        for wire in sync.added + sync.modified {
            guard let account = accountsByPlaidId[wire.accountId] else { continue }
            let transaction: Transaction
            if let existing = byPlaidId[wire.transactionId] {
                transaction = existing
            } else if let pendingId = wire.pendingTransactionId, let posted = byPlaidId[pendingId] {
                // A pending transaction just posted: reuse its local row and
                // migrate the id in place instead of creating a duplicate.
                byPlaidId[pendingId] = nil
                posted.plaidTransactionId = wire.transactionId
                byPlaidId[wire.transactionId] = posted
                transaction = posted
            } else {
                let fresh = Transaction(
                    date: .now,
                    amount: 0,
                    merchantName: "",
                    category: .other
                )
                fresh.plaidTransactionId = wire.transactionId
                context.insert(fresh)
                byPlaidId[wire.transactionId] = fresh
                transaction = fresh
            }

            // Plaid: positive = money out. Local model: positive = money in.
            transaction.amount = Self.money(-wire.amount)
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
