import SwiftUI
import SwiftData

struct AccountsListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var accounts: [Account]
    @State private var showingAddAccount = false

    private var grouped: [(AccountCategory, [Account])] {
        AccountCategory.allCases.compactMap { category in
            let matches = accounts.filter { $0.type.category == category }
            return matches.isEmpty ? nil : (category, matches)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if accounts.isEmpty {
                    ContentUnavailableView {
                        Label("No accounts yet", systemImage: "creditcard")
                    } description: {
                        Text("Tap + to add your first account — enter it manually or link your bank securely.")
                    }
                }

                ForEach(grouped, id: \.0) { category, items in
                    Section(category.displayName) {
                        ForEach(items) { account in
                            NavigationLink(value: account) {
                                AccountRow(account: account)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    modelContext.delete(account)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .refreshable {
                await SyncEngine.shared.syncAll(context: modelContext)
            }
            .navigationDestination(for: Account.self) { account in
                AccountDetailView(account: account)
            }
            .navigationTitle("Accounts")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingAddAccount = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddAccount) {
                AddAccountView()
            }
        }
    }
}

private struct AccountRow: View {
    let account: Account

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(account.name)
                Text(account.type.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(account.balance.currencyString)
                .foregroundStyle(account.type.isLiability ? .red : .primary)
        }
    }
}
