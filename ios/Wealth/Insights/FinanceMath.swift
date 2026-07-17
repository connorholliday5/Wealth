import Foundation

/// Pure money/derivation helpers shared by InsightsEngine and PaycheckAllocationEngine.
/// Keeps the "cash on hand", "monthly bills", and "highest-rate debt" definitions in
/// one place so the deterministic engines agree. Additive only — InsightsEngine keeps
/// its existing inline logic for now; these mirror it so a later refactor is a drop-in.
enum FinanceMath {
    /// Sum of checking + savings balances. Mirrors the cash definition in InsightsEngine.
    static func cashOnHand(_ accounts: [Account]) -> Decimal {
        accounts
            .filter { $0.type == .checking || $0.type == .savings }
            .reduce(Decimal(0)) { $0 + $1.balance }
    }

    /// Sum of every bill's monthlyEquivalent (recurring monthly outflow).
    static func monthlyBillsTotal(_ bills: [Bill]) -> Decimal {
        bills.reduce(Decimal(0)) { $0 + $1.monthlyEquivalent }
    }

    /// Common emergency-fund target = `months` × monthly bills (default 3).
    static func emergencyFundTarget(bills: [Bill], months: Int = 3) -> Decimal {
        monthlyBillsTotal(bills) * Decimal(months)
    }

    /// Effective annual rate for a liability: loans store it in `interestRate`,
    /// credit cards in `apr`. Prefer `interestRate`, fall back to `apr`, so both
    /// kinds of debt participate in "highest-rate" decisions.
    static func effectiveAPR(_ account: Account) -> Double? {
        account.interestRate ?? account.apr
    }

    /// Highest effective-rate liability with a positive balance, if any.
    static func highestRateDebt(_ accounts: [Account]) -> Account? {
        accounts
            .filter { $0.type.isLiability && $0.balance > 0 }
            .max { (effectiveAPR($0) ?? 0) < (effectiveAPR($1) ?? 0) }
    }

    /// Calendar months remaining in the current year, inclusive of the current month (>= 1).
    static func monthsLeftInYear(asOf date: Date = .now) -> Int {
        max(1, 12 - Calendar.current.component(.month, from: date) + 1)
    }

    /// The monthly payment we can assume for a debt: the sum of bills linked to
    /// it (normalized to monthly), falling back to its stored minimum payment.
    static func effectiveMonthlyPayment(for account: Account, bills: [Bill]) -> Decimal {
        let linked = bills
            .filter { $0.linkedAccount?.id == account.id }
            .reduce(Decimal(0)) { $0 + $1.monthlyEquivalent }
        if linked > 0 { return linked }
        return account.minimumPayment ?? 0
    }
}
