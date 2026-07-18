import Foundation

/// Deterministic, rule-based "advisor": every insight here is computed from your
/// own data with simple, explainable personal-finance heuristics. No external
/// AI service is called and no financial data leaves the device.
enum InsightsEngine {
    static func generate(
        accounts: [Account],
        bills: [Bill],
        transactions: [Transaction],
        budgets: [Budget] = [],
        asOf now: Date = .now
    ) -> [Insight] {
        var insights: [Insight] = []
        insights.append(contentsOf: creditUtilizationInsights(accounts: accounts))
        insights.append(contentsOf: emergencyFundInsight(accounts: accounts, bills: bills, transactions: transactions, asOf: now))
        insights.append(contentsOf: debtPriorityInsight(accounts: accounts))
        insights.append(contentsOf: contributionRoomInsights(accounts: accounts, asOf: now))
        insights.append(contentsOf: employerMatchInsights(accounts: accounts))
        insights.append(contentsOf: cashFlowInsight(accounts: accounts, bills: bills, asOf: now))
        insights.append(contentsOf: savingsRateInsight(transactions: transactions, asOf: now))
        insights.append(contentsOf: topSpendingInsight(transactions: transactions, asOf: now))
        insights.append(contentsOf: budgetInsights(budgets: budgets, transactions: transactions, asOf: now))
        return insights
    }

    /// Categories that represent moving money, not spending it. Counting these
    /// as expenses would make saving money look like overspending.
    static let nonSpendingCategories: Set<SpendingCategory> = [.income, .savingsTransfer, .debtPayment, .workBenefit]

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

    private static func emergencyFundInsight(accounts: [Account], bills: [Bill], transactions: [Transaction], asOf now: Date) -> [Insight] {
        let cash = FinanceMath.cashOnHand(accounts)
        // Bills alone understate real living costs — include everyday spending.
        let monthlyCosts = FinanceMath.monthlyLivingCosts(bills: bills, transactions: transactions, asOf: now)
        guard monthlyCosts > 0 else { return [] }
        let monthsCovered = (cash / monthlyCosts) as NSDecimalNumber
        let months = monthsCovered.doubleValue

        if months < 1 {
            return [Insight(
                title: "Emergency fund is thin",
                message: "Your cash covers less than a month of real costs \u{2014} bills plus everyday spending run about \(monthlyCosts.currencyString)/mo against \(cash.currencyString) on hand. Build toward 3-6 months before investing aggressively.",
                severity: .warning
            )]
        } else if months < 3 {
            return [Insight(
                title: "Building your emergency fund",
                message: "You have about \(String(format: "%.1f", months)) months of living costs saved (bills plus everyday spending). Keep going toward a 3-6 month cushion.",
                severity: .info
            )]
        } else {
            return [Insight(
                title: "Emergency fund looks solid",
                message: "You have about \(String(format: "%.1f", months)) months of living costs in cash \u{2014} that's a healthy cushion.",
                severity: .success
            )]
        }
    }

    private static func debtPriorityInsight(accounts: [Account]) -> [Insight] {
        // effectiveAPR reads loans (interestRate) AND credit cards (apr), so a
        // 23% card correctly outranks a 6% loan — previously cards were invisible here.
        guard let highest = FinanceMath.highestRateDebt(accounts),
              let rate = FinanceMath.effectiveAPR(highest), rate > 0 else { return [] }
        let severity: InsightSeverity = rate >= 15 ? .warning : .info
        return [Insight(
            title: "Focus extra payments on \(highest.name)",
            message: "\(highest.name) has your highest rate at \(String(format: "%.2f", rate))% APR. After minimums on everything else, send extra payments here first (debt avalanche) to minimize total interest.",
            severity: severity
        )]
    }

    private static func contributionRoomInsights(accounts: [Account], asOf now: Date) -> [Insight] {
        let monthsLeft = FinanceMath.monthsLeftInYear(asOf: now)
        let year = Calendar.current.component(.year, from: now)
        let trackable = accounts.filter { $0.type.isWorkBenefit || $0.type == .rothIRA || $0.type == .traditionalIRA }

        return trackable.compactMap { account -> Insight? in
            let limit = account.contributionLimitOverride ?? ContributionLimits.defaultAnnualLimit(for: account.type, year: year)
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

    private static func cashFlowInsight(accounts: [Account], bills: [Bill], asOf now: Date) -> [Insight] {
        let checking = accounts.filter { $0.type == .checking }.reduce(Decimal(0)) { $0 + $1.balance }
        let startOfToday = Calendar.current.startOfDay(for: now)
        guard let cutoff = Calendar.current.date(byAdding: .day, value: 14, to: now) else { return [] }
        // Only bills that will actually hit checking: due within the window
        // (not stale past-due rows) and not already deducted from a paycheck.
        let dueSoon = bills
            .filter { !$0.isPayrollDeduction && $0.nextDueDate >= startOfToday && $0.nextDueDate <= cutoff }
            .reduce(Decimal(0)) { $0 + $1.amount }
        guard dueSoon > 0, dueSoon > checking else { return [] }
        return [Insight(
            title: "Possible cash flow gap",
            message: "You have \(dueSoon.currencyString) in bills due in the next two weeks but only \(checking.currencyString) in checking. Consider transferring from savings before due dates hit.",
            severity: .warning
        )]
    }

    private static func savingsRateInsight(transactions: [Transaction], asOf now: Date) -> [Insight] {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: now) else { return [] }
        let recent = transactions.filter { $0.date >= cutoff }
        let income = recent.filter { $0.category == .income }.reduce(Decimal(0)) { $0 + $1.amount }
        // Money moved into savings/investments or debt principal is SAVED, not
        // spent — the old logic counted it as spending, so saving lowered your rate.
        let expenses = recent
            .filter { $0.amount < 0 && !nonSpendingCategories.contains($0.category) }
            .reduce(Decimal(0)) { $0 + (-$1.amount) }
        guard income > 0 else { return [] }
        let rate = ((income - expenses) / income) as NSDecimalNumber
        let pct = rate.doubleValue * 100
        let severity: InsightSeverity = pct < 10 ? .warning : (pct < 20 ? .info : .success)
        return [Insight(
            title: "Savings rate: \(Int(pct))%",
            message: pct < 20
                ? "You kept about \(Int(pct))% of income after spending over the last 30 days. A common target is 20% \u{2014} look for room in discretionary categories."
                : "You kept about \(Int(pct))% of income after spending over the last 30 days \u{2014} at or above the common 20% target. Great work.",
            severity: severity
        )]
    }

    private static func topSpendingInsight(transactions: [Transaction], asOf now: Date) -> [Insight] {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: now) else { return [] }
        let recent = transactions.filter { $0.date >= cutoff && $0.amount < 0 && !nonSpendingCategories.contains($0.category) }
        let totals = Dictionary(grouping: recent, by: \.category)
            .mapValues { $0.reduce(Decimal(0)) { $0 + (-$1.amount) } }
        guard let top = totals.max(by: { $0.value < $1.value }) else { return [] }
        return [Insight(
            title: "Biggest spending category: \(top.key.displayName)",
            message: "You spent \(top.value.currencyString) on \(top.key.displayName) in the last 30 days \u{2014} your largest discretionary category.",
            severity: .info
        )]
    }

    private static func budgetInsights(budgets: [Budget], transactions: [Transaction], asOf now: Date) -> [Insight] {
        guard !budgets.isEmpty else { return [] }
        let spent = BudgetMath.monthToDateSpending(transactions: transactions, asOf: now)
        return budgets.compactMap { budget -> Insight? in
            guard budget.monthlyLimit > 0 else { return nil }
            let used = spent[budget.category] ?? 0
            let fraction = ((used / budget.monthlyLimit) as NSDecimalNumber).doubleValue
            if fraction >= 1 {
                return Insight(
                    title: "Over budget: \(budget.category.displayName)",
                    message: "You've spent \(used.currencyString) of your \(budget.monthlyLimit.currencyString) \(budget.category.displayName) budget this month.",
                    severity: .warning
                )
            } else if fraction >= 0.85 {
                return Insight(
                    title: "Approaching budget: \(budget.category.displayName)",
                    message: "You've used \(Int(fraction * 100))% of your \(budget.monthlyLimit.currencyString) \(budget.category.displayName) budget with the month still going.",
                    severity: .info
                )
            }
            return nil
        }
    }
}
