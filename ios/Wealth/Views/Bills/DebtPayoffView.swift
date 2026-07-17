import SwiftUI
import SwiftData

enum PayoffStrategy: String, CaseIterable, Identifiable, Hashable {
    case avalanche
    case snowball

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .avalanche: return "Avalanche (highest rate first)"
        case .snowball: return "Snowball (smallest balance first)"
        }
    }
}

struct DebtPayoffView: View {
    @Query private var accounts: [Account]
    @Query private var bills: [Bill]
    @State private var strategy: PayoffStrategy = .avalanche
    @State private var extraPaymentText = "0"

    private var debts: [Account] {
        accounts.filter { $0.type.isLiability && $0.balance > 0 }
    }

    private var ordered: [Account] {
        switch strategy {
        case .avalanche:
            return debts.sorted { ($0.interestRate ?? $0.apr ?? 0) > ($1.interestRate ?? $1.apr ?? 0) }
        case .snowball:
            return debts.sorted { $0.balance < $1.balance }
        }
    }

    private var extraPayment: Decimal {
        Decimal(userInput: extraPaymentText) ?? 0
    }

    private var inputs: [DebtInput] {
        ordered.map { account in
            DebtInput(
                id: account.id,
                name: account.name,
                balance: account.balance,
                annualRatePercent: account.interestRate ?? account.apr ?? 0,
                monthlyPayment: FinanceMath.effectiveMonthlyPayment(for: account, bills: bills)
            )
        }
    }

    private var result: DebtPayoffResult {
        LoanPayoffCalculator.simulate(orderedDebts: inputs, extra: extraPayment)
    }

    /// True when at least one debt has no payment we can project from.
    private var hasMissingPayments: Bool {
        inputs.contains { $0.monthlyPayment <= 0 }
    }

    var body: some View {
        Form {
            if debts.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("No debts to pay off", systemImage: "checkmark.seal.fill")
                    } description: {
                        Text("Add a credit card or loan with a balance and its payment, and you'll see exactly when it'll be gone.")
                    }
                }
            } else {
                Section {
                    Picker("Strategy", selection: $strategy) {
                        ForEach(PayoffStrategy.allCases) { strategy in
                            Text(strategy.displayName).tag(strategy)
                        }
                    }
                    .pickerStyle(.inline)
                    TextField("Extra monthly payment", text: $extraPaymentText)
                        .keyboardType(.decimalPad)
                }

                debtFreeSection

                Section {
                    ForEach(Array(ordered.enumerated()), id: \.element.id) { index, debt in
                        DebtPayoffRow(
                            index: index,
                            debt: debt,
                            payment: FinanceMath.effectiveMonthlyPayment(for: debt, bills: bills),
                            extra: index == 0 ? extraPayment : 0,
                            line: result.lines.first { $0.id == debt.id }
                        )
                    }
                } header: {
                    Text("Payoff Order")
                } footer: {
                    Text(strategy == .avalanche
                         ? "Avalanche puts every extra dollar toward the highest-rate debt first, then rolls each freed-up payment onto the next — the least total interest."
                         : "Snowball attacks the smallest balance first for quick wins, rolling each freed-up payment onto the next.")
                }

                if hasMissingPayments {
                    Section {
                        Label("Some debts have no payment set, so they can't be projected. Add a minimum payment on the account, or a linked bill.", systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Debt Payoff")
    }

    @ViewBuilder private var debtFreeSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text("Debt-Free Date")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let date = result.debtFreeDate, let months = result.totalMonths {
                    Text(date.formatted(.dateTime.month(.wide).year()))
                        .font(.system(size: 30, weight: .bold))
                    Text("\(monthsDurationString(months)) from now · \(result.totalInterest.currencyString) total interest")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Not on track")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(.orange)
                    Text("At these payments, the balances aren't shrinking. Add an extra monthly payment above to find a number that works.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

private struct DebtPayoffRow: View {
    let index: Int
    let debt: Account
    let payment: Decimal
    let extra: Decimal
    let line: DebtPayoffResult.Line?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("\(index + 1). \(debt.name)")
                Spacer()
                Text(debt.balance.currencyString)
            }
            HStack {
                if let rate = debt.interestRate ?? debt.apr {
                    Text(String(format: "%.2f%% APR", rate))
                }
                Spacer()
                if payment + extra > 0 {
                    Text("Pay \((payment + extra).currencyString)/mo")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let line, let date = line.payoffDate, let months = line.months {
                Label(
                    "Paid off \(date.formatted(.dateTime.month(.abbreviated).year())) · \(monthsDurationString(months))",
                    systemImage: "calendar.badge.checkmark"
                )
                .font(.caption)
                .foregroundStyle(.green)
            } else if payment + extra > 0 {
                Label("Payment too low to make progress", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }
}
