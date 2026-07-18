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

        XCTAssertGreaterThan(bill.advancePastDue(), 0)
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

        XCTAssertEqual(bill.advancePastDue(), 0)
    }

    func testFutureBillDoesNotAdvance() throws {
        let ctx = try TestSupport.makeContext()
        let bill = Bill(name: "Insurance", amount: 120, kind: .insurance, frequency: .monthly,
                        nextDueDate: TestSupport.daysFromNow(10))
        ctx.insert(bill)

        XCTAssertEqual(bill.advancePastDue(), 0)
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

    func testMonthEndAnchorSnapsBackAfterShortMonth() {
        // Due the 31st: advancing over a short month clamps (e.g. Feb 28) but
        // must snap BACK to the 31st afterward instead of drifting forever.
        var components = DateComponents(year: 2026, month: 1, day: 31, hour: 12)
        let jan31 = Calendar.current.date(from: components)!
        let feb = BillFrequency.monthly.nextDate(after: jan31, anchorDay: 31)
        let mar = BillFrequency.monthly.nextDate(after: feb, anchorDay: 31)

        XCTAssertEqual(Calendar.current.component(.day, from: feb), 28)   // 2026: not a leap year
        XCTAssertEqual(Calendar.current.component(.month, from: feb), 2)
        XCTAssertEqual(Calendar.current.component(.day, from: mar), 31)   // snapped back
        XCTAssertEqual(Calendar.current.component(.month, from: mar), 3)

        // And without an anchor it still moves forward a month.
        components = DateComponents(year: 2026, month: 4, day: 15)
        let apr15 = Calendar.current.date(from: components)!
        let may = BillFrequency.monthly.nextDate(after: apr15)
        XCTAssertEqual(Calendar.current.component(.day, from: may), 15)
        XCTAssertEqual(Calendar.current.component(.month, from: may), 5)
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
