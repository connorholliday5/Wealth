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

            // Live, read-only holdings for linked investment accounts. Renders
            // nothing for cash/credit/loan or manual accounts (guarded inside).
            HoldingsSection(account: account)

            AccountEditSection(account: account)

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

/// Fixes the "can never correct it later" problem: rate, minimum payment,
/// credit limit, and employer-match details are all editable after creation.
/// Without an editable credit limit, the utilization insight could never fire
/// for manually-added cards.
private struct AccountEditSection: View {
    @Bindable var account: Account

    @State private var rateText = ""
    @State private var minimumText = ""
    @State private var limitText = ""
    @State private var matchText = ""
    @State private var loaded = false

    private var isDebt: Bool {
        account.type.category == .loan || account.type.category == .credit
    }

    var body: some View {
        Section {
            TextField("Account name", text: $account.name)
            if isDebt {
                HStack {
                    Text("APR %")
                    Spacer()
                    TextField("e.g. 22.99", text: $rateText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 120)
                }
                HStack {
                    Text("Minimum payment")
                    Spacer()
                    TextField("e.g. 35", text: $minimumText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 120)
                }
            }
            if account.type == .creditCard {
                HStack {
                    Text("Credit limit")
                    Spacer()
                    TextField("e.g. 5000", text: $limitText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 120)
                }
            }
            if account.type.isWorkBenefit {
                HStack {
                    Text("Employer match %")
                    Spacer()
                    TextField("e.g. 4", text: $matchText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 120)
                }
            }
        } header: {
            Text("Edit Details")
        } footer: {
            Text("Changes apply as you type. Rate and payment feed the payoff planner; credit limit powers the utilization check.")
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let rate = account.interestRate ?? account.apr { rateText = String(format: "%.2f", rate) }
            if let minimum = account.minimumPayment { minimumText = "\(minimum)" }
            if let limit = account.creditLimit { limitText = "\(limit)" }
            if let match = account.employerMatchPercent { matchText = String(format: "%.1f", match) }
        }
        .onChange(of: rateText) { _, text in
            guard let rate = Double(userInput: text) else { return }
            if account.type == .creditCard {
                account.apr = rate
            } else {
                account.interestRate = rate
            }
        }
        .onChange(of: minimumText) { _, text in
            if let minimum = Decimal(userInput: text) { account.minimumPayment = minimum }
        }
        .onChange(of: limitText) { _, text in
            if let limit = Decimal(userInput: text), limit > 0 { account.creditLimit = limit }
        }
        .onChange(of: matchText) { _, text in
            if let match = Double(userInput: text) { account.employerMatchPercent = match }
        }
    }
}
