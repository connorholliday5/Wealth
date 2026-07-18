import XCTest
import SwiftData
@testable import Wealth

@MainActor
final class InsightsEngineTests: XCTestCase {

    // Regression for the credit-card blind spot: cards store their rate in
    // `apr`, and the debt-priority rule must see it.
    func testDebtPriorityPicksCreditCardOverLowerRateLoan() throws {
        let ctx = try TestSupport.makeContext()
        let card = Account(name: "Visa", type: .creditCard, balance: 1_500)
        card.apr = 22.99
        let loan = Account(name: "Auto", type: .autoLoan, balance: 9_000)
        loan.interestRate = 6.2
        [card, loan].forEach(ctx.insert)

        let insights = InsightsEngine.generate(accounts: [card, loan], bills: [], transactions: [])
        let debtInsight = insights.first { $0.title.contains("Focus extra payments") }

        XCTAssertNotNil(debtInsight)
        XCTAssertTrue(debtInsight!.title.contains("Visa"), "22.99% card must outrank 6.2% loan, got: \(debtInsight!.title)")
    }

    // Regression: moving money into savings must NOT lower the savings rate.
    func testSavingsRateExcludesTransfersAndDebtPayments() throws {
        let ctx = try TestSupport.makeContext()
        let income = Transaction(date: .now, amount: 1_000, merchantName: "Paycheck", category: .income)
        let groceries = Transaction(date: .now, amount: -200, merchantName: "Market", category: .groceries)
        let transfer = Transaction(date: .now, amount: -500, merchantName: "To Savings", category: .savingsTransfer)
        let debtPay = Transaction(date: .now, amount: -100, merchantName: "Card Payment", category: .debtPayment)
        [income, groceries, transfer, debtPay].forEach(ctx.insert)

        let insights = InsightsEngine.generate(
            accounts: [], bills: [],
            transactions: [income, groceries, transfer, debtPay]
        )
        let rateInsight = insights.first { $0.title.contains("Savings rate") }

        // Only groceries counts as spending: (1000 - 200) / 1000 = 80%.
        XCTAssertNotNil(rateInsight)
        XCTAssertTrue(rateInsight!.title.contains("80"), "expected 80%, got: \(rateInsight!.title)")
    }

    // Regression: payroll-deducted premiums and stale past-due bills must not
    // trigger a false cash-flow warning.
    func testCashFlowIgnoresPayrollDeductionsAndPastDue() throws {
        let ctx = try TestSupport.makeContext()
        let checking = Account(name: "Checking", type: .checking, balance: 500)
        ctx.insert(checking)

        // $1000 payroll premium due tomorrow: already taken from pay.
        let premium = Bill(name: "Health", amount: 1_000, kind: .workBenefitPremium,
                           frequency: .semimonthly, nextDueDate: TestSupport.daysFromNow(1),
                           isPayrollDeduction: true)
        // $2000 bill that's 40 days PAST due: stale, not a next-two-weeks event.
        let stale = Bill(name: "Old Rent", amount: 2_000, kind: .rent,
                         frequency: .monthly, nextDueDate: TestSupport.daysFromNow(-40))
        // $100 real bill due soon — under the $500 in checking, so no warning.
        let internet = Bill(name: "Internet", amount: 100, kind: .utility,
                            frequency: .monthly, nextDueDate: TestSupport.daysFromNow(3))
        [premium, stale, internet].forEach(ctx.insert)

        let insights = InsightsEngine.generate(
            accounts: [checking], bills: [premium, stale, internet], transactions: []
        )
        XCTAssertFalse(
            insights.contains { $0.title.contains("cash flow") || $0.title.contains("Cash flow") || $0.title.contains("cash flow gap") || $0.title.contains("Possible cash") },
            "no warning expected: only $100 of real bills vs $500 checking"
        )
    }

    func testEmergencyFundUsesLivingCostsNotJustBills() throws {
        let ctx = try TestSupport.makeContext()
        let checking = Account(name: "Checking", type: .checking, balance: 3_000)
        ctx.insert(checking)
        let rent = Bill(name: "Rent", amount: 1_000, kind: .rent, frequency: .monthly,
                        nextDueDate: TestSupport.daysFromNow(10))
        ctx.insert(rent)
        // $2000/mo of groceries makes real costs $3000/mo => exactly 1 month covered.
        let groceries = Transaction(date: TestSupport.daysFromNow(-5), amount: -2_000,
                                    merchantName: "Market", category: .groceries)
        ctx.insert(groceries)

        let insights = InsightsEngine.generate(
            accounts: [checking], bills: [rent], transactions: [groceries]
        )
        let ef = insights.first { $0.title.lowercased().contains("emergency") || $0.title.contains("fund") }
        XCTAssertNotNil(ef)
        // 3000 cash / 3000 monthly costs = 1.0 months -> the "building" tier,
        // not the "solid" (>=3 months) tier bills-only math would report.
        XCTAssertNotEqual(ef!.severity, .success)
    }

    func testBudgetInsightFiresWhenOverLimit() throws {
        let ctx = try TestSupport.makeContext()
        let budget = Budget(category: .dining, monthlyLimit: 100)
        ctx.insert(budget)
        let splurge = Transaction(date: .now, amount: -150, merchantName: "Omakase", category: .dining)
        ctx.insert(splurge)

        let insights = InsightsEngine.generate(
            accounts: [], bills: [], transactions: [splurge], budgets: [budget]
        )
        XCTAssertTrue(insights.contains { $0.title.contains("Over budget") && $0.title.contains("Dining") })
    }
}
