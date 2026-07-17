import XCTest
@testable import Wealth

final class LoanPayoffTests: XCTestCase {

    private func debt(_ balance: Decimal, rate: Double, payment: Decimal, name: String = "Debt") -> DebtInput {
        DebtInput(id: UUID(), name: name, balance: balance, annualRatePercent: rate, monthlyPayment: payment)
    }

    func testZeroInterestPaysOffExactly() {
        let result = LoanPayoffCalculator.simulate(
            orderedDebts: [debt(1200, rate: 0, payment: 100)],
            extra: 0
        )
        XCTAssertEqual(result.totalMonths, 12)
        XCTAssertTrue(result.isFeasible)
        assertDecimalEqual(result.totalInterest, 0, accuracy: 0.01)
    }

    func testStandardAmortization() {
        // $1000 at 12% APR, $100/mo pays off in ~11 months.
        let result = LoanPayoffCalculator.simulate(
            orderedDebts: [debt(1000, rate: 12, payment: 100)],
            extra: 0
        )
        XCTAssertNotNil(result.totalMonths)
        XCTAssertEqual(result.totalMonths ?? 0, 11, accuracy: 1)
        XCTAssertGreaterThan(result.totalInterest, 0)
    }

    func testPaymentBelowInterestNeverPaysOff() {
        // $1000 at 24% APR accrues $20/mo; a $20 payment only covers interest.
        let result = LoanPayoffCalculator.simulate(
            orderedDebts: [debt(1000, rate: 24, payment: 20)],
            extra: 0
        )
        XCTAssertNil(result.totalMonths)
        XCTAssertFalse(result.isFeasible)
        XCTAssertNil(result.lines.first?.months)
    }

    func testExtraPaymentAcceleratesPayoff() {
        let base = LoanPayoffCalculator.simulate(orderedDebts: [debt(1000, rate: 12, payment: 100)], extra: 0)
        let boosted = LoanPayoffCalculator.simulate(orderedDebts: [debt(1000, rate: 12, payment: 100)], extra: 100)
        XCTAssertNotNil(base.totalMonths)
        XCTAssertNotNil(boosted.totalMonths)
        XCTAssertLessThan(boosted.totalMonths!, base.totalMonths!)
        XCTAssertLessThan(boosted.totalInterest, base.totalInterest)  // less time = less interest
    }

    func testFreedPaymentRollsToNextDebt() {
        // A: $500 @ 0%, $100/mo → clears at month 5, freeing $100 that rolls onto B.
        // B: $1000 @ 0%, $100/mo → then $200/mo, clearing at month 8 (not 10).
        let a = debt(500, rate: 0, payment: 100, name: "A")
        let b = debt(1000, rate: 0, payment: 100, name: "B")
        let result = LoanPayoffCalculator.simulate(orderedDebts: [a, b], extra: 0)

        let lineA = result.lines.first { $0.name == "A" }
        let lineB = result.lines.first { $0.name == "B" }
        XCTAssertEqual(lineA?.months, 5)
        XCTAssertEqual(lineB?.months, 8)          // rollover, would be 10 without it
        XCTAssertEqual(result.totalMonths, 8)
    }

    func testNoDebtsIsFeasibleAtZeroMonths() {
        let result = LoanPayoffCalculator.simulate(orderedDebts: [], extra: 0)
        XCTAssertEqual(result.totalMonths, 0)
        XCTAssertTrue(result.isFeasible)
    }

    func testPayoffDateIsInTheFuture() {
        let result = LoanPayoffCalculator.simulate(orderedDebts: [debt(1200, rate: 0, payment: 100)], extra: 0)
        XCTAssertNotNil(result.debtFreeDate)
        XCTAssertGreaterThan(result.debtFreeDate!, .now)
    }
}
