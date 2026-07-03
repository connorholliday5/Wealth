import SwiftUI
import SwiftData
import Charts

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var accounts: [Account]
    @Query(sort: \Bill.nextDueDate) private var bills: [Bill]
    @Query(sort: \NetWorthSnapshot.date) private var snapshots: [NetWorthSnapshot]
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @ObservedObject private var sync = SyncEngine.shared

    private var netWorth: Decimal {
        accounts.reduce(0) { $0 + $1.netWorthContribution }
    }

    private var upcomingBills: [Bill] {
        let cutoff = Calendar.current.date(byAdding: .day, value: 14, to: .now) ?? .now
        return bills.filter { $0.nextDueDate <= cutoff }
    }

    /// Last ~90 days of history; the chart only appears once there are two points.
    private var chartSnapshots: [NetWorthSnapshot] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -90, to: .now) ?? .distantPast
        return snapshots.filter { $0.date >= cutoff }
    }

    private var recentTransactions: [Transaction] {
        Array(transactions.prefix(6))
    }

    var body: some View {
        NavigationStack {
            List {
                if accounts.isEmpty {
                    Section {
                        ContentUnavailableView {
                            Label("Welcome to Wealth", systemImage: "chart.line.uptrend.xyaxis")
                        } description: {
                            Text("Add your checking, savings, cards, loans, and retirement accounts in the Accounts tab — or link them automatically — and your net worth, bills, and advisor light up here.")
                        }
                    }
                } else {
                    netWorthSection
                }

                Section {
                    NavigationLink {
                        PaycheckPlannerView()
                    } label: {
                        Label("Plan a Paycheck", systemImage: "dollarsign.arrow.circlepath")
                    }
                }

                if !accounts.isEmpty {
                    categorySection
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

                if !recentTransactions.isEmpty {
                    Section("Recent Activity") {
                        ForEach(recentTransactions) { transaction in
                            TransactionRow(transaction: transaction)
                        }
                    }
                }
            }
            .navigationTitle("Wealth")
            .refreshable {
                await sync.syncAll(context: modelContext)
            }
        }
    }

    private var netWorthSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text("Net Worth")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(netWorth.currencyString)
                    .font(.system(size: 36, weight: .bold))

                if chartSnapshots.count >= 2 {
                    Chart(chartSnapshots) { snapshot in
                        LineMark(
                            x: .value("Date", snapshot.date),
                            y: .value("Net Worth", NSDecimalNumber(decimal: snapshot.value).doubleValue)
                        )
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .interpolationMethod(.monotone)

                        AreaMark(
                            x: .value("Date", snapshot.date),
                            y: .value("Net Worth", NSDecimalNumber(decimal: snapshot.value).doubleValue)
                        )
                        .foregroundStyle(.linearGradient(
                            colors: [Color.accentColor.opacity(0.2), .clear],
                            startPoint: .top, endPoint: .bottom
                        ))
                        .interpolationMethod(.monotone)
                    }
                    .foregroundStyle(Color.accentColor)
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                    .frame(height: 70)
                    .padding(.top, 4)
                }

                syncStatusLine
            }
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder private var syncStatusLine: some View {
        if sync.isSyncing {
            Label("Syncing…", systemImage: "arrow.triangle.2.circlepath")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if let error = sync.lastSyncError {
            Label(error, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
        } else if let last = sync.lastSyncedAt {
            Text("Updated \(last.formatted(.relative(presentation: .named)))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var categorySection: some View {
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
    }
}

/// Compact transaction row shared by the Dashboard and account detail screens.
struct TransactionRow: View {
    let transaction: Transaction

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.merchantName)
                HStack(spacing: 4) {
                    Text(transaction.date.formatted(date: .abbreviated, time: .omitted))
                    Text("·")
                    Text(transaction.category.displayName)
                    if transaction.pending {
                        Text("· Pending")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Text(transaction.amount.currencyString)
                .monospacedDigit()
                .foregroundStyle(transaction.amount >= 0 ? .green : .primary)
        }
    }
}
