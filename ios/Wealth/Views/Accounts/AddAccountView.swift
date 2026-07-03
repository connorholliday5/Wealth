import SwiftUI
import SwiftData

struct AddAccountView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @StateObject private var plaidLinkManager = PlaidLinkManager()

    @State private var name = ""
    @State private var type: AccountType = .checking
    @State private var balanceText = ""
    @State private var institutionName = ""

    // Credit card / loan
    @State private var interestRateText = ""
    @State private var minimumPaymentText = ""

    // Employer benefits (401k / HSA)
    @State private var employerName = ""
    @State private var employerMatchText = ""
    @State private var ytdContributionText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Link Automatically") {
                    Button {
                        plaidLinkManager.presentLink()
                    } label: {
                        Label("Connect a bank, card, or 401(k)/Roth IRA", systemImage: "link")
                    }
                    Text("Uses Plaid to securely pull balances and transactions. Requires the Wealth proxy server to be configured with your Plaid API keys.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Or Enter Manually") {
                    TextField("Account name", text: $name)
                    TextField("Institution (optional)", text: $institutionName)
                    Picker("Type", selection: $type) {
                        ForEach(AccountType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    TextField(type.isLiability ? "Amount owed" : "Balance", text: $balanceText)
                        .keyboardType(.decimalPad)
                }

                if type.category == .credit || type.category == .loan {
                    Section("Rate & Payment") {
                        TextField("Interest rate (APR %)", text: $interestRateText)
                            .keyboardType(.decimalPad)
                        TextField("Minimum/typical payment", text: $minimumPaymentText)
                            .keyboardType(.decimalPad)
                    }
                }

                if type.isWorkBenefit {
                    Section("Employer Benefit") {
                        TextField("Employer name", text: $employerName)
                        TextField("Employer match (%)", text: $employerMatchText)
                            .keyboardType(.decimalPad)
                        TextField("Contributed so far this year", text: $ytdContributionText)
                            .keyboardType(.decimalPad)
                    }
                }
            }
            .navigationTitle("Add Account")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .disabled(name.isEmpty || balanceText.isEmpty)
                }
            }
            .onChange(of: plaidLinkManager.linkedAccounts) { _, linked in
                guard !linked.isEmpty else { return }
                for account in linked {
                    modelContext.insert(account)
                }
                // Pull transaction history, APRs, and loan terms for the new
                // accounts right away rather than waiting for the next auto-sync.
                let context = modelContext
                Task { await SyncEngine.shared.syncAll(context: context) }
                dismiss()
            }
            .alert(
                "Couldn't Link Account",
                isPresented: Binding(
                    get: { plaidLinkManager.errorMessage != nil },
                    set: { if !$0 { plaidLinkManager.errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(plaidLinkManager.errorMessage ?? "")
            }
        }
    }

    private func save() {
        guard let balance = Decimal(userInput: balanceText) else { return }
        let account = Account(
            name: name,
            type: type,
            balance: balance,
            isManual: true,
            institutionName: institutionName.isEmpty ? nil : institutionName
        )
        if let rate = Double(interestRateText) {
            account.interestRate = rate
            account.apr = rate
        }
        if let payment = Decimal(userInput: minimumPaymentText) {
            account.minimumPayment = payment
        }
        if type.isWorkBenefit {
            account.employerName = employerName.isEmpty ? nil : employerName
            account.employerMatchPercent = Double(employerMatchText)
            account.yearToDateContribution = Decimal(userInput: ytdContributionText)
            account.contributionYear = Calendar.current.component(.year, from: .now)
            account.contributionLimitOverride = ContributionLimits.defaultAnnualLimit(for: type)
        }
        modelContext.insert(account)
        dismiss()
    }
}
