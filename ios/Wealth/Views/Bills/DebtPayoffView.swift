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
    @State private var strategy: PayoffStrategy = .avalanche
    @State private var extraPaymentText = "0"

    private var debts: [Account] {
        accounts.filter { $0.type.isLiability && $0.balance > 0 }
    }

    private var ordered: [Account] {
        switch strategy {
        case .avalanche:
            return debts.sorted { ($0.interestRate ?? 0) > ($1.interestRate ?? 0) }
        case .snowball:
            return debts.sorted { $0.balance < $1.balance }
        }
    }

    private var extraPayment: Decimal {
        Decimal(string: extraPaymentText) ?? 0
    }

    var body: some View {
        Form {
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

            Section("Payoff Order") {
                if debts.isEmpty {
                    Text("No outstanding debts \u{1F389}")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(ordered.enumerated()), id: \.element.id) { index, debt in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text("\(index + 1). \(debt.name)")
                                Spacer()
                                Text(debt.balance.currencyString)
                            }
                            HStack {
                                if let rate = debt.interestRate {
                                    Text("\(rate, specifier: "%.2f")% APR")
                                }
                                Spacer()
                                if index == 0, let payment = debt.minimumPayment {
                                    Text("Pay \((payment + extraPayment).currencyString)/mo")
                                } else if let payment = debt.minimumPayment {
                                    Text("Pay \(payment.currencyString)/mo (minimum)")
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                    Text(strategy == .avalanche
                         ? "Put every extra dollar toward the highest-interest debt first; it minimizes total interest paid."
                         : "Put every extra dollar toward the smallest balance first; it builds momentum with quick wins.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Debt Payoff")
    }
}
