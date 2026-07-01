import XCTest
import SwiftData
@testable import Wealth

@MainActor
final class FinanceMathTests: XCTestCase {

    func testCashOnHandSumsCheckingAndSavingsOnly() throws {
        let ctx = try TestSupport.makeContext()
        let checking = Account(name: "Checking", type: .checking, balance: 1000)
        let savings = Account(name: "Savings", type: .savings, balance: 2000)
        let card = Account(name: "Card", type: .creditCard, balance: 500)
        [checking, savings, card].forEach(ctx.insert)

        assertDecimalEqual(FinanceMath.cashOnHand([checking, savings, card]), 3000)
    }

    func testMonthlyBillsTotalNormalizesFrequency() {
        // monthly 100 => 100/mo; annual 1200 => 100/mo; total ~200/mo.
        let monthly = Bill(name: "M", amount: 100, kind: .utility, frequency: .monthly, nextDueDate: .now)
        let annual = Bill(name: "A", amount: 1200, kind: .insurance, frequency: .annual, nextDueDate: .now)
        assertDecimalEqual(FinanceMath.monthlyBillsTotal([monthly, annual]), 200, accuracy: 0.01)
    }

    func testEffectiveAPRPrefersInterestRateThenApr() {
        let loan = Account(name: "Loan", type: .autoLoan, balance: 100)
        loan.interestRate = 6.5
        let card = Account(name: "Card", type: .creditCard, balance: 100)
        card.apr = 22.99

        XCTAssertEqual(FinanceMath.effectiveAPR(loan), 6.5)
        XCTAssertEqual(FinanceMath.effectiveAPR(card), 22.99)
    }

    func testHighestRateDebtPicksCreditCardViaApr() {
        let loan = Account(name: "Student", type: .studentLoan, balance: 10000)
        loan.interestRate = 5.5
        let card = Account(name: "Visa", type: .creditCard, balance: 1500)
        card.apr = 22.99
        let asset = Account(name: "Savings", type: .savings, balance: 9000) // not a liability

        XCTAssertEqual(FinanceMath.highestRateDebt([loan, card, asset])?.name, "Visa")
    }

    func testHighestRateDebtIgnoresZeroBalanceAndAssets() {
        let paidOff = Account(name: "Paid", type: .autoLoan, balance: 0)
        paidOff.interestRate = 9.9
        let asset = Account(name: "Checking", type: .checking, balance: 5000)

        XCTAssertNil(FinanceMath.highestRateDebt([paidOff, asset]))
    }
}
