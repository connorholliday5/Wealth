import Foundation

/// User-selectable pay cadence. Drives the "reserve window" for near-term bills
/// and how annual/monthly targets are paced per check.
enum PayFrequency: String, CaseIterable, Identifiable, Hashable {
    case weekly
    case biweekly
    case semimonthly
    case monthly

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .weekly: return "Weekly"
        case .biweekly: return "Every 2 weeks"
        case .semimonthly: return "Twice a month"
        case .monthly: return "Monthly"
        }
    }

    /// Days of upcoming bills a single paycheck should keep covered.
    var reserveWindowDays: Int {
        switch self {
        case .weekly: return 7
        case .biweekly: return 14
        case .semimonthly: return 15
        case .monthly: return 31
        }
    }

    /// Average paychecks per month — used to convert monthly targets into
    /// per-check amounts (52/12 weekly, 26/12 biweekly, 2, 1). Without this,
    /// a biweekly earner would be told to invest a full month's pace on every
    /// check, more than double the intended rate.
    var paychecksPerMonth: Decimal {
        switch self {
        case .weekly: return Decimal(52) / Decimal(12)
        case .biweekly: return Decimal(26) / Decimal(12)
        case .semimonthly: return 2
        case .monthly: return 1
        }
    }
}

/// Where a slice of the paycheck is being recommended to go.
enum AllocationCategory: String, Hashable {
    case bills
    case emergencyFund
    case debtPaydown
    case investing
    case savingsGoal
    case discretionary

    var displayName: String {
        switch self {
        case .bills: return "Upcoming Bills"
        case .emergencyFund: return "Emergency Fund"
        case .debtPaydown: return "Debt Paydown"
        case .investing: return "Investing"
        case .savingsGoal: return "Savings Goals"
        case .discretionary: return "Free to Spend / Save"
        }
    }

    var symbolName: String {
        switch self {
        case .bills: return "calendar"
        case .emergencyFund: return "shield.lefthalf.filled"
        case .debtPaydown: return "creditcard"
        case .investing: return "chart.line.uptrend.xyaxis"
        case .savingsGoal: return "flag.checkered"
        case .discretionary: return "sparkles"
        }
    }
}

/// One line of the waterfall recommendation.
struct AllocationLine: Identifiable {
    let id = UUID()
    let label: String                 // destination label, e.g. account name or "Upcoming bills"
    let category: AllocationCategory
    let targetAccountID: UUID?        // optional concrete account to move money into / pay
    let suggestedAmount: Decimal
    let rationale: String             // short human-readable why
}

/// Full result of the waterfall.
struct PaycheckPlan {
    let paycheck: Decimal
    let payFrequency: PayFrequency
    let lines: [AllocationLine]
    let warnings: [String]
    let totalAllocated: Decimal
    let unmetBillShortfall: Decimal   // > 0 when paycheck can't cover step-1 bills

    var isFeasible: Bool { unmetBillShortfall == 0 }
}

/// Deterministic "where should this paycheck go" engine. Pure: no I/O, no
/// randomness, Decimal math throughout. Waterfall order reflects standard
/// personal-finance priority: near-term bills → employer match (via payroll) →
/// emergency fund → high-interest debt → tax-advantaged investing → savings
/// goals → discretionary.
enum PaycheckAllocationEngine {
    // Thresholds / pacing knobs — explicit so they're easy to tune & test.
    // Shares are constructed as Decimal(n)/100 to avoid Double->Decimal binary error.
    private static let emergencyMonths = 3
    private static let emergencyMaxPaycheckShare = Decimal(20) / 100   // up to 20% of paycheck
    private static let debtAPRThreshold = 7.0                          // only target debt above this
    private static let debtMaxPaycheckShare = Decimal(15) / 100        // up to 15% of paycheck
    private static let goalsMaxPaycheckShare = Decimal(10) / 100       // cap for undated goals

    static func plan(
        paycheck: Decimal,
        payFrequency: PayFrequency,
        accounts: [Account],
        bills: [Bill],
        transactions: [Transaction] = [],
        goals: [SavingsGoal] = [],
        asOf now: Date = .now
    ) -> PaycheckPlan {

        var lines: [AllocationLine] = []
        var warnings: [String] = []
        var remaining = paycheck        // running balance, never goes negative
        let original = paycheck         // % shares are of the original paycheck
        let checksPerMonth = payFrequency.paychecksPerMonth

        // Guard: non-positive paycheck -> empty plan.
        guard paycheck > 0 else {
            return PaycheckPlan(
                paycheck: paycheck, payFrequency: payFrequency,
                lines: [], warnings: ["Enter a paycheck amount to see a plan."],
                totalAllocated: 0, unmetBillShortfall: 0
            )
        }

        // ---- STEP 0: Employer match nudge (informational, costs $0 of take-home) ----
        // 401(k) contributions are payroll-deducted, so they can't be allocated
        // from take-home pay — but capturing the match outranks everything except
        // keeping the lights on, so surface it before the cash waterfall.
        if let matched = accounts.first(where: { $0.type == .fourOhOneK && ($0.employerMatchPercent ?? 0) > 0 }) {
            let limit = matched.contributionLimitOverride
                ?? ContributionLimits.defaultAnnualLimit(for: .fourOhOneK, year: Calendar.current.component(.year, from: now))
            let contributed = matched.yearToDateContribution ?? 0
            if let limit, contributed < limit {
                warnings.append(
                    "First priority is free money: make sure your \(matched.name) payroll contribution "
                    + "captures the full \(String(format: "%.1f", matched.employerMatchPercent ?? 0))% employer match "
                    + "— that's set with your employer, not from this check."
                )
            }
        }

        // ---- STEP 1: Bills due within the reserve window (exclude payroll deductions) ----
        let windowEnd = Calendar.current.date(
            byAdding: .day, value: payFrequency.reserveWindowDays, to: now
        ) ?? now
        let dueSoon = bills.filter {
            !$0.isPayrollDeduction && $0.nextDueDate <= windowEnd
        }
        let billsDue = dueSoon.reduce(Decimal(0)) { $0 + $1.amount }

        if billsDue > 0 {
            let reserve = min(remaining, billsDue)
            let shortfall = billsDue - reserve      // > 0 only if paycheck < billsDue

            lines.append(AllocationLine(
                label: "Upcoming bills",
                category: .bills,
                targetAccountID: nil,
                suggestedAmount: reserve,
                rationale: "Covers \(dueSoon.count) bill(s) totaling \(billsDue.currencyString) "
                         + "due in the next \(payFrequency.reserveWindowDays) days."
            ))
            remaining -= reserve

            if shortfall > 0 {
                // Paycheck can't even cover near-term bills -> warn and STOP the waterfall.
                warnings.append(
                    "This paycheck (\(original.currencyString)) doesn't fully cover "
                    + "\(billsDue.currencyString) of bills due in the next "
                    + "\(payFrequency.reserveWindowDays) days. You're short "
                    + "\(shortfall.currencyString) — consider drawing from savings."
                )
                return PaycheckPlan(
                    paycheck: original, payFrequency: payFrequency,
                    lines: lines, warnings: warnings,
                    totalAllocated: original - remaining,
                    unmetBillShortfall: shortfall
                )
            }
        }

        // ---- STEP 2: Emergency fund top-up (realistic living costs, not just bills) ----
        let efTarget = FinanceMath.emergencyFundTarget(bills: bills, transactions: transactions, months: emergencyMonths, asOf: now)
        let cash = FinanceMath.cashOnHand(accounts)
        if remaining > 0, efTarget > 0, cash < efTarget {
            let gap = efTarget - cash
            let cap = original * emergencyMaxPaycheckShare
            let amount = min(min(remaining, gap), cap)
            if amount > 0 {
                let savings = accounts.first { $0.type == .savings }
                lines.append(AllocationLine(
                    label: savings?.name ?? "Savings",
                    category: .emergencyFund,
                    targetAccountID: savings?.id,
                    suggestedAmount: amount,
                    rationale: "You have \(cash.currencyString) of a "
                             + "\(efTarget.currencyString) (\(emergencyMonths)-month living costs) "
                             + "emergency fund. This moves you toward the target."
                ))
                remaining -= amount
            }
        }

        // ---- STEP 3: High-interest debt extra payment ----
        if remaining > 0,
           let debt = FinanceMath.highestRateDebt(accounts),
           let rate = FinanceMath.effectiveAPR(debt), rate > debtAPRThreshold {
            let cap = original * debtMaxPaycheckShare
            let amount = min(min(remaining, debt.balance), cap)
            if amount > 0 {
                lines.append(AllocationLine(
                    label: debt.name,
                    category: .debtPaydown,
                    targetAccountID: debt.id,
                    suggestedAmount: amount,
                    rationale: "\(debt.name) is your highest-rate debt at "
                             + "\(String(format: "%.2f", rate))% APR. An extra payment here "
                             + "beats most guaranteed returns (debt avalanche)."
                ))
                remaining -= amount
            }
        }

        // ---- STEP 4: Tax-advantaged investing (paced per check to year-end) ----
        if remaining > 0 {
            let monthsLeft = FinanceMath.monthsLeftInYear(asOf: now)
            let year = Calendar.current.component(.year, from: now)
            // Matched 401(k)s first (free money), then HSA (triple tax advantage),
            // Roth IRA, then unmatched 401(k)s.
            let matched = accounts.filter { $0.type == .fourOhOneK && ($0.employerMatchPercent ?? 0) > 0 }
            let unmatched = accounts.filter { $0.type == .fourOhOneK && ($0.employerMatchPercent ?? 0) <= 0 }
            let candidates = matched
                + accounts.filter { $0.type == .hsa }
                + accounts.filter { $0.type == .rothIRA }
                + unmatched
            for account in candidates {
                guard remaining > 0 else { break }
                let limit = account.contributionLimitOverride
                          ?? ContributionLimits.defaultAnnualLimit(for: account.type, year: year)
                guard let limit, limit > 0 else { continue }
                let contributed = account.yearToDateContribution ?? 0
                let room = limit - contributed
                guard room > 0 else { continue }

                let pacedMonthly = room / Decimal(monthsLeft)
                let pacedPerCheck = pacedMonthly / checksPerMonth
                let amount = min(min(remaining, room), pacedPerCheck)
                guard amount > 0 else { continue }

                lines.append(AllocationLine(
                    label: account.name,
                    category: .investing,
                    targetAccountID: account.id,
                    suggestedAmount: amount,
                    rationale: "You've put in \(contributed.currencyString) of "
                             + "\(limit.currencyString) this year. About "
                             + "\(pacedMonthly.currencyString)/month (\(pacedPerCheck.currencyString) per check) "
                             + "maxes it by year-end."
                ))
                remaining -= amount
            }
        }

        // ---- STEP 5: Savings goals ----
        if remaining > 0, !goals.isEmpty {
            let active = goals
                .filter { !$0.isComplete }
                .sorted {
                    switch ($0.targetDate, $1.targetDate) {
                    case let (a?, b?): return a < b
                    case (.some, .none): return true
                    case (.none, .some): return false
                    case (.none, .none): return $0.createdAt < $1.createdAt
                    }
                }
            var goalsBudget = min(remaining, original * goalsMaxPaycheckShare)
            for goal in active {
                guard goalsBudget > 0 else { break }
                // Dated goals get their required pace; undated ones split the cap.
                let monthlyNeed = goal.monthlyNeeded(asOf: now) ?? (original * goalsMaxPaycheckShare * checksPerMonth)
                let perCheck = monthlyNeed / checksPerMonth
                let amount = min(min(goalsBudget, goal.remaining), perCheck)
                guard amount > 0 else { continue }
                lines.append(AllocationLine(
                    label: goal.name,
                    category: .savingsGoal,
                    targetAccountID: nil,
                    suggestedAmount: amount,
                    rationale: goal.targetDate.map {
                        "\(goal.remaining.currencyString) to go by \($0.formatted(.dateTime.month(.abbreviated).year())) — this keeps you on pace."
                    } ?? "\(goal.remaining.currencyString) to go — steady contributions get you there."
                ))
                goalsBudget -= amount
                remaining -= amount
            }
        }

        // ---- STEP 6: Discretionary remainder ----
        if remaining > 0 {
            lines.append(AllocationLine(
                label: "Free to spend or save",
                category: .discretionary,
                targetAccountID: nil,
                suggestedAmount: remaining,
                rationale: "After bills, savings, debt, investing, and goals, this is yours to "
                         + "spend or stash as you like."
            ))
            remaining = 0
        }

        return PaycheckPlan(
            paycheck: original, payFrequency: payFrequency,
            lines: lines, warnings: warnings,
            totalAllocated: original - remaining,   // == original here
            unmetBillShortfall: 0
        )
    }
}
