import SwiftUI
import SwiftData

struct DashboardView: View {
    @Query private var accounts: [Account]
    @Query(sort: \Bill.nextDueDate) private var bills: [Bill]

    private var netWorth: Decimal {
        accounts.reduce(0) { $0 + $1.netWorthContribution }
    }

    private var upcomingBills: [Bill] {
        bills.filter { $0.nextDueDate <= Calendar.current.date(byAdding: .day, value: 14, to: .now)! }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Net Worth")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(netWorth.currencyString)
                            .font(.system(size: 36, weight: .bold))
                    }
                    .padding(.vertical, 8)
                }

                Section {
                    NavigationLink {
                        PaycheckPlannerView()
                    } label: {
                        Label("Plan a Paycheck", systemImage: "dollarsign.arrow.circlepath")
                    }
                }

                Section("By Category") {
                    ForEach(AccountCategory.allCases, id: \.self) { category in
                        let total = accounts
                            .filter { $0.type.category == category }
                            .reduce(Decimal(0)) { $0 + $1.balance }
                        if total != 0 {
                            HStack {
                                Text(category.displayName)
                                Spacer()
                                Text(total.currencyString)
                                    .foregroundStyle(category == .credit || category == .loan ? .red : .primary)
                            }
                        }
                    }
                }

                if !upcomingBills.isEmpty {
                    Section("Upcoming Bills") {
                        ForEach(upcomingBills) { bill in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(bill.name)
                                    Text(bill.nextDueDate.dayCountdownString)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(bill.amount.currencyString)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Wealth")
        }
    }
}
