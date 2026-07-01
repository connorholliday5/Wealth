import SwiftUI
import SwiftData

/// "I just got paid — where should it go?" Enter a take-home amount and a pay
/// cadence; the deterministic PaycheckAllocationEngine returns a priority
/// waterfall computed from your real accounts and bills. Recomputes live.
struct PaycheckPlannerView: View {
    @Query private var accounts: [Account]
    @Query private var bills: [Bill]

    @State private var amountText = ""
    @State private var payFrequency: PayFrequency = .biweekly

    private var paycheck: Decimal { Decimal(string: amountText) ?? 0 }

    private var plan: PaycheckPlan {
        PaycheckAllocationEngine.plan(
            paycheck: paycheck,
            payFrequency: payFrequency,
            accounts: accounts,
            bills: bills
        )
    }

    var body: some View {
        Form {
            Section("Your Paycheck") {
                TextField("Amount (after tax)", text: $amountText)
                    .keyboardType(.decimalPad)
                Picker("Pay frequency", selection: $payFrequency) {
                    ForEach(PayFrequency.allCases) { freq in
                        Text(freq.displayName).tag(freq)
                    }
                }
            }

            if paycheck <= 0 {
                Section {
                    ContentUnavailableView(
                        "Enter a paycheck",
                        systemImage: "dollarsign.circle",
                        description: Text("Type your take-home pay to see where it should go.")
                    )
                }
            } else {
                if !plan.warnings.isEmpty {
                    Section {
                        ForEach(plan.warnings, id: \.self) { warning in
                            Label(warning, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .font(.subheadline)
                        }
                    }
                }

                Section("Recommended Plan") {
                    ForEach(plan.lines) { line in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: line.category.symbolName)
                                .foregroundStyle(.tint)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(line.label).font(.headline)
                                    Spacer()
                                    Text(line.suggestedAmount.currencyString)
                                        .font(.headline.monospacedDigit())
                                }
                                Text(line.rationale)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                } footer: {
                    if plan.isFeasible {
                        Text("Allocated \(plan.totalAllocated.currencyString) of "
                           + "\(plan.paycheck.currencyString). This is guidance computed from "
                           + "your own data — not financial advice.")
                    }
                }
            }
        }
        .navigationTitle("Paycheck Planner")
    }
}

#Preview {
    NavigationStack { PaycheckPlannerView() }
        .modelContainer(SampleData.container)
}
