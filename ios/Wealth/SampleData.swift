import Foundation
import SwiftData

/// Populates the in-memory preview store with realistic data so SwiftUI
/// previews and the simulator have something to show without manual entry.
enum SampleData {
    @MainActor
    static var container: ModelContainer = {
        let schema = Schema([Account.self, Transaction.self, Bill.self, NetWorthSnapshot.self, Budget.self, SavingsGoal.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext

        let checking = Account(name: "Everyday Checking", type: .checking, balance: 3_200)
        let savings = Account(name: "Emergency Fund", type: .savings, balance: 9_000)
        let creditCard = Account(name: "Visa Rewards", type: .creditCard, balance: 1_450)
        creditCard.creditLimit = 5_000
        creditCard.apr = 22.99

        let rothIRA = Account(name: "Roth IRA", type: .rothIRA, balance: 18_400)
        rothIRA.yearToDateContribution = 3_000
        // No contributionLimitOverride: the account tracks the current tax
        // year's IRS limit automatically. Overrides are for special cases only.

        let fourOhOneK = Account(name: "Acme Corp 401(k)", type: .fourOhOneK, balance: 42_000)
        fourOhOneK.employerName = "Acme Corp"
        fourOhOneK.employerMatchPercent = 4
        fourOhOneK.yearToDateContribution = 9_000

        let hsa = Account(name: "Acme Corp HSA", type: .hsa, balance: 2_100)
        hsa.employerName = "Acme Corp"
        hsa.yearToDateContribution = 800

        let studentLoan = Account(name: "Federal Student Loan", type: .studentLoan, balance: 18_500)
        studentLoan.interestRate = 5.5
        studentLoan.minimumPayment = 210

        let autoLoan = Account(name: "Honda Civic Loan", type: .autoLoan, balance: 9_800)
        autoLoan.interestRate = 6.2
        autoLoan.minimumPayment = 320

        for account in [checking, savings, creditCard, rothIRA, fourOhOneK, hsa, studentLoan, autoLoan] {
            context.insert(account)
        }

        let rent = Bill(name: "Rent", amount: 1_800, kind: .rent, frequency: .monthly, nextDueDate: .now.addingDays(5), autopay: true)
        let internetBill = Bill(name: "Internet", amount: 70, kind: .utility, frequency: .monthly, nextDueDate: .now.addingDays(10))
        let healthPremium = Bill(name: "Health Insurance Premium", amount: 145, kind: .workBenefitPremium, frequency: .semimonthly, nextDueDate: .now.addingDays(3), isPayrollDeduction: true)
        let studentPayment = Bill(name: "Student Loan Payment", amount: 210, kind: .loanPayment, frequency: .monthly, nextDueDate: .now.addingDays(12), linkedAccount: studentLoan)
        let cardPayment = Bill(name: "Visa Payment", amount: 100, kind: .creditCardPayment, frequency: .monthly, nextDueDate: .now.addingDays(8), linkedAccount: creditCard)
        let netflix = Bill(name: "Netflix", amount: 16, kind: .subscription, frequency: .monthly, nextDueDate: .now.addingDays(20))
        let spotify = Bill(name: "Spotify", amount: 12, kind: .subscription, frequency: .monthly, nextDueDate: .now.addingDays(25))

        for bill in [rent, internetBill, healthPremium, studentPayment, cardPayment, netflix, spotify] {
            context.insert(bill)
        }

        let categorized: [(String, Decimal, SpendingCategory, Int)] = [
            ("Paycheck", 4_200, .income, -2),
            ("Whole Foods", -180, .groceries, -3),
            ("Chipotle", -42, .dining, -5),
            ("Shell Gas", -55, .transportation, -7),
            ("Netflix", -16, .subscriptions, -9),
            ("Amazon", -120, .shopping, -10),
            ("Gym Membership", -45, .subscriptions, -14),
        ]
        for (merchant, amount, category, daysAgo) in categorized {
            let transaction = Transaction(date: .now.addingDays(daysAgo), amount: amount, merchantName: merchant, category: category)
            transaction.account = checking
            context.insert(transaction)
        }

        context.insert(Budget(category: .dining, monthlyLimit: 250))
        context.insert(Budget(category: .shopping, monthlyLimit: 200))
        context.insert(SavingsGoal(name: "Japan Trip", targetAmount: 3_000, savedAmount: 1_100, targetDate: .now.addingDays(240)))

        // Net-worth history for the Dashboard chart: a gentle upward trend.
        for weeksAgo in stride(from: 12, through: 0, by: -1) {
            let value = Decimal(43_000 + (12 - weeksAgo) * 450)
            context.insert(NetWorthSnapshot(date: .now.addingDays(-7 * weeksAgo), value: value))
        }

        return container
    }()
}

private extension Date {
    func addingDays(_ days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: self) ?? self
    }
}
