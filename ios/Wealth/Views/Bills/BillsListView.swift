import SwiftUI
import SwiftData

struct BillsListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Bill.nextDueDate) private var bills: [Bill]
    @State private var showingAddBill = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        DebtPayoffView()
                    } label: {
                        Label("Debt Payoff Planner", systemImage: "chart.line.downtrend.xyaxis")
                    }
                }

                Section("Bills & Payments") {
                    ForEach(bills) { bill in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(bill.name)
                                if bill.isPayrollDeduction {
                                    Text("Payroll")
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(.blue.opacity(0.15))
                                        .clipShape(Capsule())
                                }
                                Spacer()
                                Text(bill.amount.currencyString)
                            }
                            HStack {
                                Text("\(bill.kind.displayName) · \(bill.frequency.displayName)")
                                Spacer()
                                Text(bill.nextDueDate.dayCountdownString)
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets { modelContext.delete(bills[index]) }
                    }
                }
            }
            .navigationTitle("Bills")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingAddBill = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddBill) {
                AddBillView()
            }
        }
    }
}
