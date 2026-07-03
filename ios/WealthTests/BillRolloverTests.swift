import XCTest
import SwiftData
@testable import Wealth

@MainActor
final class BillRolloverTests: XCTestCase {

    func testOverdueMonthlyBillAdvancesToFuture() throws {
        let ctx = try TestSupport.makeContext()
        let bill = Bill(name: "Rent", amount: 1800, kind: .rent, frequency: .monthly,
                        nextDueDate: TestSupport.daysFromNow(-45))
        ctx.insert(bill)

        XCTAssertTrue(bill.advancePastDue())
        // Must land today or later, and within one cycle of today.
        let startOfToday = Calendar.current.startOfDay(for: .now)
        XCTAssertGreaterThanOrEqual(bill.nextDueDate, startOfToday)
        let oneMonthOut = Calendar.current.date(byAdding: .month, value: 1, to: .now)!
        XCTAssertLessThanOrEqual(bill.nextDueDate, oneMonthOut)
    }

    func testDueTodayDoesNotAdvance() throws {
        let ctx = try TestSupport.makeContext()
        let bill = Bill(name: "Internet", amount: 70, kind: .utility, frequency: .monthly,
                        nextDueDate: .now)
        ctx.insert(bill)

        XCTAssertFalse(bill.advancePastDue())
    }

    func testFutureBillDoesNotAdvance() throws {
        let ctx = try TestSupport.makeContext()
        let bill = Bill(name: "Insurance", amount: 120, kind: .insurance, frequency: .monthly,
                        nextDueDate: TestSupport.daysFromNow(10))
        ctx.insert(bill)

        XCTAssertFalse(bill.advancePastDue())
    }

    func testMarkPaidAdvancesOneCycleAndPaysDownLinkedDebt() throws {
        let ctx = try TestSupport.makeContext()
        let card = Account(name: "Visa", type: .creditCard, balance: 500)
        ctx.insert(card)
        let due = TestSupport.daysFromNow(2)
        let bill = Bill(name: "Visa Payment", amount: 100, kind: .creditCardPayment,
                        frequency: .monthly, nextDueDate: due, linkedAccount: card)
        ctx.insert(bill)

        bill.markPaid()

        assertDecimalEqual(card.balance, 400)
        let expected = Calendar.current.date(byAdding: .month, value: 1, to: due)!
        XCTAssertEqual(
            Calendar.current.startOfDay(for: bill.nextDueDate),
            Calendar.current.startOfDay(for: expected)
        )
    }

    func testMarkPaidNeverPushesDebtNegative() throws {
        let ctx = try TestSupport.makeContext()
        let loan = Account(name: "Loan", type: .otherLoan, balance: 50)
        ctx.insert(loan)
        let bill = Bill(name: "Loan Payment", amount: 100, kind: .loanPayment,
                        frequency: .monthly, nextDueDate: .now, linkedAccount: loan)
        ctx.insert(bill)

        bill.markPaid()

        assertDecimalEqual(loan.balance, 0)
    }
}
