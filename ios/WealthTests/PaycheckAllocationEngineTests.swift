import XCTest
import SwiftData
@testable import Wealth

@MainActor
final class PaycheckAllocationEngineTests: XCTestCase {

    func testZeroPaycheckReturnsEmptyPlanWithWarning() {
        let plan = PaycheckAllocationEngine.plan(
            paycheck: 0, payFrequency: .biweekly, accounts: [], bills: []
        )
        XCTAssertTrue(plan.lines.isEmpty)
        XCTAssertFalse(plan.warnings.isEmpty)
        assertDecimalEqual(plan.totalAllocated, 0)
    }

    func testFeasiblePaycheckAllocatesEntireAmount() throws {
        let ctx = try TestSupport.makeContext()
        let checking = Account(name: "Checking", type: .checking, balance: 3000)
        let savings = Account(name: "Savings", type: .savings, balance: 9000)
        let roth = Account(name: "Roth", type: .rothIRA, balance: 10000)
        roth.yearToDateContribution = 1000
        [checking, savings, roth].forEach(ctx.insert)

        let rent = Bill(name: "Rent", amount: 1500, kind: .rent, frequency: .monthly,
                        nextDueDate: TestSupport.daysFromNow(3))
        ctx.insert(rent)

        let plan = PaycheckAllocationEngine.plan(
            paycheck: 4000, payFrequency: .biweekly,
            accounts: [checking, savings, roth], bills: [rent]
        )

        XCTAssertTrue(plan.isFeasible)
        let sum = plan.lines.reduce(Decimal(0)) { $0 + $1.suggestedAmount }
        assertDecimalEqual(sum, 4000)            // the core invariant: nothing lost or created
        assertDecimalEqual(plan.totalAllocated, 4000)
    }

    func testUnderfundedPaycheckReportsShortfallAndStops() throws {
        let ctx = try TestSupport.makeContext()
        let rent = Bill(name: "Rent", amount: 2000, kind: .rent, frequency: .monthly,
                        nextDueDate: TestSupport.daysFromNow(2))
        ctx.insert(rent)

        let plan = PaycheckAllocationEngine.plan(
            paycheck: 500, payFrequency: .biweekly, accounts: [], bills: [rent]
        )

        XCTAssertFalse(plan.isFeasible)
        XCTAssertGreaterThan(plan.unmetBillShortfall, 0)
        XCTAssertEqual(plan.lines.count, 1)                  // stops after the bills line
        XCTAssertEqual(plan.lines.first?.category, .bills)
    }

    func testPayrollDeductionsExcludedFromBillReserve() throws {
        let ctx = try TestSupport.makeContext()
        // A $1,000 payroll premium due tomorrow would sink a $200 check IF counted.
        let premium = Bill(name: "Health", amount: 1000, kind: .workBenefitPremium,
                           frequency: .semimonthly, nextDueDate: TestSupport.daysFromNow(1),
                           isPayrollDeduction: true)
        ctx.insert(premium)

        let plan = PaycheckAllocationEngine.plan(
            paycheck: 200, payFrequency: .biweekly, accounts: [], bills: [premium]
        )

        XCTAssertTrue(plan.isFeasible)
        XCTAssertFalse(plan.lines.contains { $0.category == .bills })
    }

    func testCreditCardBecomesDebtPaydownTarget() throws {
        let ctx = try TestSupport.makeContext()
        let card = Account(name: "Visa", type: .creditCard, balance: 1500)
        card.apr = 22.99
        let loan = Account(name: "Auto", type: .autoLoan, balance: 9000)
        loan.interestRate = 6.2                              // below the 7% threshold
        [card, loan].forEach(ctx.insert)

        let plan = PaycheckAllocationEngine.plan(
            paycheck: 3000, payFrequency: .biweekly, accounts: [card, loan], bills: []
        )

        let debtLine = plan.lines.first { $0.category == .debtPaydown }
        XCTAssertEqual(debtLine?.label, "Visa")
        XCTAssertEqual(debtLine?.targetAccountID, card.id)
    }

    func testEmergencyFundCappedAtTwentyPercentOfPaycheck() throws {
        let ctx = try TestSupport.makeContext()
        let checking = Account(name: "Checking", type: .checking, balance: 0)
        ctx.insert(checking)
        // Rent due in 40 days is outside the 14-day reserve window, so it only
        // drives the emergency-fund target, not the step-1 bill reserve.
        let rent = Bill(name: "Rent", amount: 3000, kind: .rent, frequency: .monthly,
                        nextDueDate: TestSupport.daysFromNow(40))
        ctx.insert(rent)

        let plan = PaycheckAllocationEngine.plan(
            paycheck: 1000, payFrequency: .biweekly, accounts: [checking], bills: [rent]
        )

        let ef = plan.lines.first { $0.category == .emergencyFund }
        XCTAssertNotNil(ef)
        assertDecimalEqual(ef!.suggestedAmount, 200)         // 20% of $1,000
    }

    func testDeterministicAcrossRepeatedCalls() throws {
        let ctx = try TestSupport.makeContext()
        let card = Account(name: "Visa", type: .creditCard, balance: 1500)
        card.apr = 22.99
        ctx.insert(card)

        let a = PaycheckAllocationEngine.plan(paycheck: 2500, payFrequency: .monthly, accounts: [card], bills: [])
        let b = PaycheckAllocationEngine.plan(paycheck: 2500, payFrequency: .monthly, accounts: [card], bills: [])

        XCTAssertEqual(a.lines.map(\.category), b.lines.map(\.category))
        XCTAssertEqual(a.lines.map(\.suggestedAmount), b.lines.map(\.suggestedAmount))
    }
}
