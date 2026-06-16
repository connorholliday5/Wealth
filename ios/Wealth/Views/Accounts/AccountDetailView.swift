import SwiftUI
import SwiftData

struct AccountDetailView: View {
    @Bindable var account: Account

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

            if account.type.category == .credit, let limit = account.creditLimit, limit > 0 {
                let utilization = NSDecimalNumber(decimal: account.balance / limit).doubleValue
                Section("Utilization") {
                    ProgressView(value: min(utilization, 1.0))
                    Text("\(Int(utilization * 100))% of \(limit.currencyString) limit")
                        .font(.caption)
                        .foregroundStyle(utilization > 0.3 ? .red : .secondary)
                }
            }

            if account.type.category == .loan {
                Section("Loan Details") {
                    if let rate = account.interestRate {
                        LabeledContent("Interest rate", value: "\(rate, specifier: "%.2f")%")
                    }
                    if let payment = account.minimumPayment {
                        LabeledContent("Minimum payment", value: payment.currencyString)
                    }
                }
            }

            if account.type.isWorkBenefit || account.type == .rothIRA {
                ContributionSection(account: account)
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
            if let employer = account.employerName {
                LabeledContent("Employer", value: employer)
            }
            if let match = account.employerMatchPercent {
                LabeledContent("Employer match", value: "\(match, specifier: "%.1f")%")
            }
        }
    }
}
