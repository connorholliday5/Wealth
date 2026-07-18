import XCTest
import SwiftData
@testable import Wealth

@MainActor
final class AccountRecommendationTests: XCTestCase {

    func testRecommendsRothIRAWhenNoneExists() throws {
        let ctx = try TestSupport.makeContext()
        let checking = Account(name: "Checking", type: .checking, balance: 2_000)
        ctx.insert(checking)

        let recs = AccountRecommendationEngine.recommend(accounts: [checking], bills: [], transactions: [])
        XCTAssertTrue(recs.contains { $0.title.contains("Roth IRA") })
    }

    func testNoRothRecommendationWhenIRAExists() throws {
        let ctx = try TestSupport.makeContext()
        let roth = Account(name: "My Roth", type: .rothIRA, balance: 10_000)
        ctx.insert(roth)

        let recs = AccountRecommendationEngine.recommend(accounts: [roth], bills: [], transactions: [])
        XCTAssertFalse(recs.contains { $0.title.contains("Roth IRA") })
    }

    func testRecommendsSavingsAccountWhenMissing() throws {
        let ctx = try TestSupport.makeContext()
        let checking = Account(name: "Checking", type: .checking, balance: 8_000)
        ctx.insert(checking)

        let recs = AccountRecommendationEngine.recommend(accounts: [checking], bills: [], transactions: [])
        XCTAssertTrue(recs.contains { $0.title.contains("high-yield savings") })
    }

    func testFlagsIdleCashWhenCheckingFarExceedsNeeds() throws {
        let ctx = try TestSupport.makeContext()
        let checking = Account(name: "Checking", type: .checking, balance: 20_000)
        let savings = Account(name: "Savings", type: .savings, balance: 10_000)
        [checking, savings].forEach(ctx.insert)
        let rent = Bill(name: "Rent", amount: 1_000, kind: .rent, frequency: .monthly,
                        nextDueDate: TestSupport.daysFromNow(5))
        ctx.insert(rent)

        // EF target = 3 x 1000 = 3000; checking 20k >> 3k -> idle cash flagged.
        let recs = AccountRecommendationEngine.recommend(accounts: [checking, savings], bills: [rent], transactions: [])
        XCTAssertTrue(recs.contains { $0.title.contains("idle") })
    }

    func testWellSetUpUserGetsFewRecommendations() throws {
        let ctx = try TestSupport.makeContext()
        let checking = Account(name: "Checking", type: .checking, balance: 2_000)
        let savings = Account(name: "Savings", type: .savings, balance: 12_000)
        let roth = Account(name: "Roth", type: .rothIRA, balance: 15_000)
        let hsa = Account(name: "HSA", type: .hsa, balance: 3_000)
        let k401 = Account(name: "401k", type: .fourOhOneK, balance: 40_000)
        [checking, savings, roth, hsa, k401].forEach(ctx.insert)
        let rent = Bill(name: "Rent", amount: 1_500, kind: .rent, frequency: .monthly,
                        nextDueDate: TestSupport.daysFromNow(5))
        ctx.insert(rent)

        let recs = AccountRecommendationEngine.recommend(
            accounts: [checking, savings, roth, hsa, k401], bills: [rent], transactions: []
        )
        XCTAssertTrue(recs.isEmpty, "fully set-up user should get no gap recommendations, got: \(recs.map(\.title))")
    }

    func testContributionLimitsAreYearAware() {
        XCTAssertEqual(ContributionLimits.defaultAnnualLimit(for: .rothIRA, year: 2025), 7_000)
        XCTAssertEqual(ContributionLimits.defaultAnnualLimit(for: .rothIRA, year: 2026), 7_500)
        XCTAssertEqual(ContributionLimits.defaultAnnualLimit(for: .fourOhOneK, year: 2026), 24_500)
        // Unknown future year falls back to the latest known table, never nil.
        XCTAssertNotNil(ContributionLimits.defaultAnnualLimit(for: .hsa, year: 2030))
    }

    func testBudgetMathExcludesNonSpending() throws {
        let ctx = try TestSupport.makeContext()
        let dining = Transaction(date: .now, amount: -50, merchantName: "Cafe", category: .dining)
        let transfer = Transaction(date: .now, amount: -900, merchantName: "To Savings", category: .savingsTransfer)
        let income = Transaction(date: .now, amount: 2_000, merchantName: "Paycheck", category: .income)
        [dining, transfer, income].forEach(ctx.insert)

        let spent = BudgetMath.monthToDateSpending(transactions: [dining, transfer, income])
        assertDecimalEqual(spent[.dining] ?? 0, 50)
        XCTAssertNil(spent[.savingsTransfer])
        XCTAssertNil(spent[.income])
    }
}
