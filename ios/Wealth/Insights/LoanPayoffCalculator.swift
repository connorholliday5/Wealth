import Foundation

/// A single debt's input to the payoff simulation. Kept free of SwiftData so it
/// can be unit-tested directly.
struct DebtInput: Identifiable {
    let id: UUID
    let name: String
    let balance: Decimal
    let annualRatePercent: Double   // e.g. 22.99; 0 if unknown
    let monthlyPayment: Decimal     // the minimum/typical payment for this debt
}

struct DebtPayoffResult {
    struct Line: Identifiable {
        let id: UUID
        let name: String
        /// Months until this debt hits zero, or nil if it never does within the cap.
        let months: Int?
        let totalInterest: Decimal
        var payoffDate: Date? {
            guard let months else { return nil }
            return Calendar.current.date(byAdding: .month, value: months, to: .now)
        }
    }

    let lines: [Line]
    /// Months until every debt is paid (the debt-free date). nil if some debt
    /// never pays off at the given payments.
    let totalMonths: Int?
    let totalInterest: Decimal

    var isFeasible: Bool { totalMonths != nil }
    var debtFreeDate: Date? {
        guard let totalMonths else { return nil }
        return Calendar.current.date(byAdding: .month, value: totalMonths, to: .now)
    }
}

/// Projects when debts will be paid off. Simulates month by month: interest
/// accrues, each debt gets its minimum, then any extra — plus the payments
/// freed up by already-cleared debts — cascades onto the highest-priority
/// remaining debt (the debt-snowball/avalanche rollover effect). The caller
/// decides priority order (avalanche vs snowball) by ordering `orderedDebts`.
enum LoanPayoffCalculator {
    /// Guardrail so a hopeless payment (never covers interest) terminates.
    static let capMonths = 1200   // 100 years

    static func simulate(orderedDebts: [DebtInput], extra: Decimal) -> DebtPayoffResult {
        struct Work {
            let id: UUID
            let name: String
            var balance: Double
            let rate: Double        // monthly
            let minimum: Double
            var interest: Double
            var payoffMonth: Int?
        }

        var work = orderedDebts.map { debt in
            Work(
                id: debt.id,
                name: debt.name,
                balance: NSDecimalNumber(decimal: debt.balance).doubleValue,
                rate: debt.annualRatePercent / 100.0 / 12.0,
                minimum: NSDecimalNumber(decimal: debt.monthlyPayment).doubleValue,
                interest: 0,
                payoffMonth: nil
            )
        }
        let extraDouble = NSDecimalNumber(decimal: extra).doubleValue

        var month = 0
        while work.contains(where: { $0.balance > 0.005 }) && month < capMonths {
            month += 1

            // 1. Interest accrues on every outstanding balance.
            for i in work.indices where work[i].balance > 0 {
                let interest = work[i].balance * work[i].rate
                work[i].balance += interest
                work[i].interest += interest
            }

            // 2. The attack pool = user's extra + the minimums freed by any
            //    already-paid-off debts.
            var pool = extraDouble
            for w in work where w.balance <= 0.005 { pool += w.minimum }

            // 3. Every still-active debt pays its own minimum.
            for i in work.indices where work[i].balance > 0 {
                work[i].balance -= min(work[i].minimum, work[i].balance)
            }

            // 4. The pool cascades down the priority order.
            for i in work.indices {
                if pool <= 0 { break }
                guard work[i].balance > 0 else { continue }
                let pay = min(pool, work[i].balance)
                work[i].balance -= pay
                pool -= pay
            }

            // 5. Record newly cleared debts.
            for i in work.indices where work[i].payoffMonth == nil && work[i].balance <= 0.005 {
                work[i].payoffMonth = month
            }
        }

        let lines = work.map {
            DebtPayoffResult.Line(id: $0.id, name: $0.name, months: $0.payoffMonth, totalInterest: Decimal($0.interest))
        }
        let allPaid = work.allSatisfy { $0.payoffMonth != nil }
        // Empty input => already debt-free: 0 months, not "infeasible".
        let totalMonths = allPaid ? (work.compactMap(\.payoffMonth).max() ?? 0) : nil
        let totalInterest = lines.reduce(Decimal(0)) { $0 + $1.totalInterest }

        return DebtPayoffResult(lines: lines, totalMonths: totalMonths, totalInterest: totalInterest)
    }
}
