import Foundation

/// Deterministic, rule-based "advisor": every insight here is computed from your
/// own data with simple, explainable personal-finance heuristics. No external
/// AI service is called and no financial data leaves the device.
enum InsightsEngine {
    static func generate(accounts: [Account], bills: [Bill], transactions: [Transaction]) -> [Insight] {
        var insights: [Insight] = []
        insights.append(contentsOf: creditUtilizationInsights(accounts: accounts))
        insights.append(contentsOf: emergencyFundInsight(accounts: accounts, bills: bills))
        insights.append(contentsOf: debtPriorityInsight(accounts: accounts))
        insights.append(contentsOf: contributionRoomInsights(accounts: accounts))
        insights.append(contentsOf: employerMatchInsights(accounts: accounts))
        insights.append(contentsOf: cashFlowInsight(accounts: accounts, bills: bills))
        insights.append(contentsOf: savingsRateInsight(transactions: transactions))
        insights.append(contentsOf: topSpendingInsight(transactions: transactions))
        return insights
    }

    private static func creditUtilizationInsights(accounts: [Account]) -> [Insight] {
        let cards = accounts.filter { $0.type == .creditCard && ($0.creditLimit ?? 0) > 0 }
        return cards.compactMap { card -> Insight? in
            guard let limit = card.creditLimit, limit > 0 else { return nil }
            let utilization = (card.balance / limit) as NSDecimalNumber
            let pct = utilization.doubleValue
            guard pct > 0.3 else { return nil }
            return Insight(
                title: "High utilization on \(card.name)",
                message: "You're using \(Int(pct * 100))% of your \(limit.currencyString) limit. Keeping it under 30% helps your credit score — paying down \(card.name) is a good next move.",
                severity: pct > 0.7 ? .warning : .info
            )
        }
    }

    private static func emergencyFundInsight(accounts: [Account], bills: [Bill]) -> [Insight] {
        let cash = accounts.filter { $0.type == .checking || $0.type == .savings }
            .reduce(Decimal(0)) { $0 + $1.balance }
        let monthlyExpenses = bills.reduce(Decimal(0)) { $0 + $1.monthlyEquivalent }
        guard monthlyExpenses > 0 else { return [] }
        let monthsCovered = (cash / monthlyExpenses) as NSDecimalNumber
        let months = monthsCovered.doubleValue

        if months < 1 {
            return [Insight(
                title: "Emergency fund is thin",
                message: "Your cash on hand covers less than a month of bills (\(cash.currencyString) vs \(monthlyExpenses.currencyString)/mo). Aim to build toward 3-6 months of expenses before investing aggressively.",
                severity: .warning
            )]
        } else if months < 3 {
            return [Insight(
                title: "Building your emergency fund",
                message: "You have about \(String(format: "%.1f", months)) months of expenses saved. Keep going toward a 3-6 month cushion.",
                severity: .info
            )]
        } else {
            return [Insight(
                title: "Emergency fund looks solid",
                message: "You have about \(String(format: "%.1f", months)) months of expenses in cash \u{2014} that's a healthy cushion.",
                severity: .success
            )]
        }
    }

    private static func debtPriorityInsight(accounts: [Account]) -> [Insight] {
        let debts = accounts.filter { $0.type.isLiability && $0.balance > 0 }
        guard let highest = debts.max(by: { ($0.interestRate ?? 0) < ($1.interestRate ?? 0) }),
              let rate = highest.interestRate, rate > 0 else { return [] }
        let severity: InsightSeverity = rate >= 15 ? .warning : .info
        return [Insight(
            title: "Focus extra payments on \(highest.name)",
            message: "\(highest.name) has your highest rate at \(String(format: "%.2f", rate))% APR. After minimums on everything else, send extra payments here first (debt avalanche) to minimize total interest.",
            severity: severity
        )]
    }

    private static func contributionRoomInsights(accounts: [Account]) -> [Insight] {
        let now = Date.now
        let monthsLeft = max(1, 12 - Calendar.current.component(.month, from: now) + 1)
        let trackable = accounts.filter { $0.type.isWorkBenefit || $0.type == .rothIRA || $0.type == .traditionalIRA }

        return trackable.compactMap { account -> Insight? in
            let limit = account.contributionLimitOverride ?? ContributionLimits.defaultAnnualLimit(for: account.type)
            guard let limit, limit > 0 else { return nil }
            let contributed = account.yearToDateContribution ?? 0
            let remaining = limit - contributed
            guard remaining > 0 else {
                return Insight(
                    title: "\(account.name) maxed out",
                    message: "Nice work \u{2014} you've hit the \(limit.currencyString) limit for \(account.type.displayName) this year.",
                    severity: .success
                )
            }
            let perMonth = (remaining / Decimal(monthsLeft))
            return Insight(
                title: "On track to max your \(account.type.displayName)?",
                message: "You've contributed \(contributed.currencyString) of \(limit.currencyString) this year. Contributing about \(perMonth.currencyString)/month for the rest of the year would max it out.",
                severity: .info
            )
        }
    }

    private static func employerMatchInsights(accounts: [Account]) -> [Insight] {
        accounts
            .filter { $0.type == .fourOhOneK && ($0.employerMatchPercent ?? 0) > 0 }
            .map { account in
                Insight(
                    title: "Don't leave employer match on the table",
                    message: "\(account.employerName ?? "Your employer") matches up to \(String(format: "%.1f", account.employerMatchPercent ?? 0))% on your \(account.name). Make sure your contribution rate is at least enough to capture the full match \u{2014} it's free money.",
                    severity: .info
                )
            }
    }

    private static func cashFlowInsight(accounts: [Account], bills: [Bill]) -> [Insight] {
        let checking = accounts.filter { $0.type == .checking }.reduce(Decimal(0)) { $0 + $1.balance }
        let next14DayCutoff = Calendar.current.date(byAdding: .day, value: 14, to: .now)!
        let dueSoon = bills.filter { $0.nextDueDate <= next14DayCutoff }.reduce(Decimal(0)) { $0 + $1.amount }
        guard dueSoon > 0, dueSoon > checking else { return [] }
        return [Insight(
            title: "Possible cash flow gap",
            message: "You have \(dueSoon.currencyString) in bills due in the next two weeks but only \(checking.currencyString) in checking. Consider transferring from savings before due dates hit.",
            severity: .warning
        )]
    }

    private static func savingsRateInsight(transactions: [Transaction]) -> [Insight] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: .now)!
        let recent = transactions.filter { $0.date >= cutoff }
        let income = recent.filter { $0.category == .income }.reduce(Decimal(0)) { $0 + $1.amount }
        let expenses = recent.filter { $0.amount < 0 }.reduce(Decimal(0)) { $0 + (-$1.amount) }
        guard income > 0 else { return [] }
        let rate = ((income - expenses) / income) as NSDecimalNumber
        let pct = rate.doubleValue * 100
        let severity: InsightSeverity = pct < 10 ? .warning : (pct < 20 ? .info : .success)
        return [Insight(
            title: "Savings rate: \(Int(pct))%",
            message: pct < 20
                ? "You saved about \(Int(pct))% of income over the last 30 days. A common target is 20% \u{2014} look for room in discretionary spending."
                : "You saved about \(Int(pct))% of income over the last 30 days \u{2014} at or above the common 20% target. Great work.",
            severity: severity
        )]
    }

    private static func topSpendingInsight(transactions: [Transaction]) -> [Insight] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: .now)!
        let excluded: Set<SpendingCategory> = [.income, .savingsTransfer, .debtPayment, .workBenefit]
        let recent = transactions.filter { $0.date >= cutoff && $0.amount < 0 && !excluded.contains($0.category) }
        let totals = Dictionary(grouping: recent, by: \.category)
            .mapValues { $0.reduce(Decimal(0)) { $0 + (-$1.amount) } }
        guard let top = totals.max(by: { $0.value < $1.value }) else { return [] }
        return [Insight(
            title: "Biggest spending category: \(top.key.displayName)",
            message: "You spent \(top.value.currencyString) on \(top.key.displayName) in the last 30 days \u{2014} your largest discretionary category.",
            severity: .info
        )]
    }
}
