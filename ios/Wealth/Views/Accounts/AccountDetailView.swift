import SwiftUI
import SwiftData

struct AccountDetailView: View {
    @Bindable var account: Account
    @Query private var bills: [Bill]
    @State private var balanceText = ""

    /// Payoff projection for this single debt at its own payment (no extra).
    private var payoffLine: DebtPayoffResult.Line? {
        guard account.type.isLiability, account.balance > 0 else { return nil }
        let payment = FinanceMath.effectiveMonthlyPayment(for: account, bills: bills)
        guard payment > 0 else { return nil }
        let input = DebtInput(
            id: account.id,
            name: account.name,
            balance: account.balance,
            annualRatePercent: account.interestRate ?? account.apr ?? 0,
            monthlyPayment: payment
        )
        return LoanPayoffCalculator.simulate(orderedDebts: [input], extra: 0).lines.first
    }

    private var recentTransactions: [Transaction] {
        account.transactions
            .sorted { $0.date > $1.date }
            .prefix(20)
            .map { $0 }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(account.type.isLiability ? "Amount Owed" : "Balance")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(account.balance.currencyString)
                        .font(.system(size: 32, weight: .bold))
                }
            }

            if account.isManual {
                Section {
                    HStack {
                        TextField(
                            account.type.isLiability ? "New amount owed" : "New balance",
                            text: $balanceText
                        )
                        .keyboardType(.decimalPad)
                        Button("Update") {
                            if let value = Decimal(userInput: balanceText) {
                                account.balance = value
                                balanceText = ""
                            }
                        }
                        .disabled(Decimal(userInput: balanceText) == nil)
                    }
                } footer: {
                    Text("Manual account — update the balance here whenever it changes.")
                }
            }

            if account.type.category == .credit, let limit = account.creditLimit, limit > 0 {
                let utilization = NSDecimalNumber(decimal: account.balance / limit).doubleValue
                Section("Utilization") {
                    ProgressView(value: min(utilization, 1.0))
                    Text("\(Int(utilization * 100))% of \(limit.currencyString) limit")
                        .font(.caption)
                        .foregroundStyle(utilization > 0.3 ? .red : .secondary)
                }
            }

            if account.type.category == .loan || account.type.category == .credit {
                Section {
                    if let rate = account.interestRate ?? account.apr {
                        LabeledContent("Interest rate", value: String(format: "%.2f%% APR", rate))
                    }
                    if let payment = account.minimumPayment {
                        LabeledContent("Minimum payment", value: payment.currencyString)
                    }
                    if let line = payoffLine, let date = line.payoffDate, let months = line.months {
                        LabeledContent("Paid off") {
                            VStack(alignment: .trailing, spacing: 1) {
                                Text(date.formatted(.dateTime.month(.abbreviated).year()))
                                Text("\(monthsDurationString(months)) · \(line.totalInterest.currencyString) interest")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Rate & Payment")
                } footer: {
                    if payoffLine == nil && account.balance > 0 {
                        Text("Add a minimum payment (or link a bill) to project a payoff date.")
                    }
                }
            }

            if account.type.isWorkBenefit || account.type == .rothIRA || account.type == .traditionalIRA {
                ContributionSection(account: account)
            }

            if !recentTransactions.isEmpty {
                Section("Recent Activity") {
                    ForEach(recentTransactions) { transaction in
                        TransactionRow(transaction: transaction)
                    }
                }
            }

            if !account.isManual {
                Section {
                    LabeledContent("Linked via", value: "Plaid")
                    if let lastSynced = account.lastSynced {
                        LabeledContent("Last synced", value: lastSynced.formatted(date: .abbreviated, time: .shortened))
                    }
                }
            }
        }
        .navigationTitle(account.name)
    }
}

private struct ContributionSection: View {
    @Bindable var account: Account
    @State private var ytdText = ""

    private var limit: Decimal {
        account.contributionLimitOverride ?? ContributionLimits.defaultAnnualLimit(for: account.type) ?? 0
    }

    private var contributed: Decimal {
        account.yearToDateContribution ?? 0
    }

    var body: some View {
        Section("\(Calendar.current.component(.year, from: .now)) Contributions") {
            if limit > 0 {
                let progress = NSDecimalNumber(decimal: contributed / limit).doubleValue
                ProgressView(value: min(progress, 1.0))
                Text("\(contributed.currencyString) of \(limit.currencyString) limit")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                TextField("Update contributed this year", text: $ytdText)
                    .keyboardType(.decimalPad)
                Button("Save") {
                    if let value = Decimal(userInput: ytdText) {
                        account.yearToDateContribution = value
                        account.contributionYear = Calendar.current.component(.year, from: .now)
                        ytdText = ""
                    }
                }
                .disabled(Decimal(userInput: ytdText) == nil)
            }
            if let employer = account.employerName {
                LabeledContent("Employer", value: employer)
            }
            if let match = account.employerMatchPercent {
                LabeledContent("Employer match", value: String(format: "%.1f%%", match))
            }
        }
    }
}
