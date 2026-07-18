import SwiftUI
import SwiftData

/// Manual transaction entry — so spending insights, budgets, and the savings
/// rate work even without a linked bank.
struct AddTransactionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var accounts: [Account]

    enum Kind: String, CaseIterable, Identifiable {
        case expense, income
        var id: String { rawValue }
    }

    @State private var kind: Kind = .expense
    @State private var amountText = ""
    @State private var merchant = ""
    @State private var category: SpendingCategory = .groceries
    @State private var date: Date = .now
    @State private var accountID: UUID?

    private var spendableAccounts: [Account] {
        accounts.filter { $0.type == .checking || $0.type == .savings || $0.type == .creditCard }
    }

    private var categoryChoices: [SpendingCategory] {
        SpendingCategory.allCases.filter { $0 != .income }
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Type", selection: $kind) {
                    Text("Expense").tag(Kind.expense)
                    Text("Income").tag(Kind.income)
                }
                .pickerStyle(.segmented)

                TextField("Amount", text: $amountText)
                    .keyboardType(.decimalPad)
                TextField(kind == .expense ? "Where (e.g. Trader Joe's)" : "Source (e.g. Paycheck)", text: $merchant)
                if kind == .expense {
                    Picker("Category", selection: $category) {
                        ForEach(categoryChoices) { category in
                            Text(category.displayName).tag(category)
                        }
                    }
                }
                DatePicker("Date", selection: $date, displayedComponents: .date)
                if !spendableAccounts.isEmpty {
                    Picker("Account (optional)", selection: $accountID) {
                        Text("None").tag(UUID?.none)
                        ForEach(spendableAccounts) { account in
                            Text(account.name).tag(Optional(account.id))
                        }
                    }
                }
            }
            .navigationTitle(kind == .expense ? "Add Purchase" : "Add Income")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .disabled(merchant.isEmpty || Decimal(userInput: amountText) == nil)
                }
            }
        }
    }

    private func save() {
        guard let amount = Decimal(userInput: amountText), amount > 0 else { return }
        let transaction = Transaction(
            date: date,
            amount: kind == .expense ? -amount : amount,
            merchantName: merchant,
            category: kind == .expense ? category : .income
        )
        if let accountID {
            transaction.account = accounts.first { $0.id == accountID }
        }
        modelContext.insert(transaction)
        dismiss()
    }
}

#Preview {
    AddTransactionView()
        .modelContainer(SampleData.container)
}
