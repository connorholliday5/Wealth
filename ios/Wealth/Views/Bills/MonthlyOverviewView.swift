import SwiftUI
import SwiftData

/// Aggregate view of recurring outflow: total monthly bills, a subscriptions
/// subtotal, a per-category breakdown, and a dedicated subscription list.
/// All figures reuse Bill.monthlyEquivalent so nothing double-counts frequency.
struct MonthlyOverviewView: View {
    @Query(sort: \Bill.nextDueDate) private var bills: [Bill]

    private var totalMonthly: Decimal {
        FinanceMath.monthlyBillsTotal(bills)
    }

    private var subscriptions: [Bill] {
        bills.filter { $0.kind == .subscription }
    }

    private var subscriptionsMonthly: Decimal {
        subscriptions.reduce(Decimal(0)) { $0 + $1.monthlyEquivalent }
    }

    /// Per-kind monthly totals, only non-zero kinds, highest first (deterministic).
    private var byKind: [(kind: BillKind, total: Decimal)] {
        Dictionary(grouping: bills, by: \.kind)
            .map { (kind: $0.key,
                    total: $0.value.reduce(Decimal(0)) { $0 + $1.monthlyEquivalent }) }
            .filter { $0.total > 0 }
            .sorted { $0.total > $1.total }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Monthly Recurring Outflow")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(totalMonthly.currencyString)
                        .font(.system(size: 32, weight: .bold))
                    Text("Subscriptions: \(subscriptionsMonthly.currencyString)/mo")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }

            Section("By Category") {
                ForEach(byKind, id: \.kind) { row in
                    HStack {
                        Text(row.kind.displayName)
                        Spacer()
                        Text("\(row.total.currencyString)/mo")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Subscriptions") {
                if subscriptions.isEmpty {
                    Text("No subscriptions tracked yet. Add a bill with type \u{201C}Subscription\u{201D} to see it here.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(subscriptions) { sub in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(sub.name)
                                Spacer()
                                Text(sub.amount.currencyString)
                            }
                            HStack {
                                Text(sub.frequency.displayName)
                                Spacer()
                                Text("\(sub.monthlyEquivalent.currencyString)/mo")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Monthly Overview")
    }
}

#Preview {
    NavigationStack { MonthlyOverviewView() }
        .modelContainer(SampleData.container)
}
