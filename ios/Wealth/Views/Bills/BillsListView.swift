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
                        MonthlyOverviewView()
                    } label: {
                        Label("Monthly Overview", systemImage: "chart.pie")
                    }
                    NavigationLink {
                        DebtPayoffView()
                    } label: {
                        Label("Debt Payoff Planner", systemImage: "chart.line.downtrend.xyaxis")
                    }
                }

                Section {
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
                                    .foregroundStyle(bill.nextDueDate < Calendar.current.startOfDay(for: .now) ? .red : .secondary)
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button {
                                bill.markPaid()
                                NotificationManager.shared.schedule(for: bill)
                            } label: {
                                Label("Mark Paid", systemImage: "checkmark.circle.fill")
                            }
                            .tint(.green)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                NotificationManager.shared.cancel(for: bill)
                                modelContext.delete(bill)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    Text("Bills & Payments")
                } footer: {
                    Text("Swipe right on a bill to mark it paid — the due date rolls to the next cycle, and payments on loans or cards reduce that balance.")
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
