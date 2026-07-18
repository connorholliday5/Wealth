import Foundation
import SwiftData

/// Housekeeping that runs at app launch: rolls overdue recurring bills forward,
/// resets year-to-date contribution tracking when the calendar year changes, and
/// records a daily net-worth snapshot for the Dashboard chart. Safe to call on
/// every launch — each step is idempotent.
@MainActor
enum MaintenanceEngine {
    static func runLaunchMaintenance(context: ModelContext) {
        let bills = (try? context.fetch(FetchDescriptor<Bill>())) ?? []
        let accounts = (try? context.fetch(FetchDescriptor<Account>())) ?? []

        rollOverdueBills(bills)
        resetContributionYearIfNeeded(accounts)
        recordDailySnapshot(accounts: accounts, context: context)
    }

    /// Advances any bill whose due date has fully passed to its next occurrence
    /// and refreshes its reminders. Without this, "upcoming bills", the paycheck
    /// planner's reserve, and notifications all decay as due dates go stale.
    /// Autopay bills that pay down a manually-tracked debt also credit the
    /// skipped payments (Plaid-linked balances are corrected by sync instead).
    static func rollOverdueBills(_ bills: [Bill], asOf now: Date = .now) {
        for bill in bills {
            let skippedCycles = bill.advancePastDue(asOf: now)
            guard skippedCycles > 0 else { continue }
            if bill.autopay,
               let account = bill.linkedAccount,
               account.type.isLiability, account.isManual {
                account.balance = max(0, account.balance - bill.amount * Decimal(skippedCycles))
            }
            NotificationManager.shared.schedule(for: bill)
        }
    }

    /// On the first launch of a new year, zero out year-to-date contributions so
    /// IRA/401(k)/HSA pacing advice starts fresh.
    static func resetContributionYearIfNeeded(_ accounts: [Account], asOf now: Date = .now) {
        let currentYear = Calendar.current.component(.year, from: now)
        for account in accounts where account.yearToDateContribution != nil {
            if let year = account.contributionYear {
                if year != currentYear {
                    account.yearToDateContribution = 0
                    account.contributionYear = currentYear
                }
            } else {
                // Legacy rows from before contributionYear existed: assume the
                // amount belongs to the current year.
                account.contributionYear = currentYear
            }
        }
    }

    /// Records today's net worth once per day (updates in place if today's
    /// point already exists, so the chart reflects the latest balances).
    static func recordDailySnapshot(accounts: [Account], context: ModelContext, asOf now: Date = .now) {
        let netWorth = accounts.reduce(Decimal(0)) { $0 + $1.netWorthContribution }
        let startOfToday = Calendar.current.startOfDay(for: now)

        let descriptor = FetchDescriptor<NetWorthSnapshot>(
            predicate: #Predicate { $0.date >= startOfToday },
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        if let today = try? context.fetch(descriptor).first {
            today.value = netWorth
        } else {
            context.insert(NetWorthSnapshot(date: now, value: netWorth))
        }
    }
}
