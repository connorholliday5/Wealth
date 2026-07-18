import SwiftUI
import SwiftData

/// This month's spending by category, with optional budgets per category.
/// Spending comes from transactions (synced or manually added); budgets are
/// simple monthly caps that also feed advisor warnings.
struct SpendingView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var transactions: [Transaction]
    @Query(sort: \Budget.monthlyLimit, order: .reverse) private var budgets: [Budget]
    @State private var showingAddBudget = false

    private var spent: [SpendingCategory: Decimal] {
        BudgetMath.monthToDateSpending(transactions: transactions)
    }

    private var totalSpent: Decimal {
        spent.values.reduce(0, +)
    }

    /// Categories worth showing: anything spent on this month or budgeted.
    private var rows: [(category: SpendingCategory, spent: Decimal, budget: Budget?)] {
        let budgetsByCategory = Dictionary(uniqueKeysWithValues: budgets.map { ($0.category, $0) })
        let categories = Set(spent.keys).union(budgetsByCategory.keys)
        return categories
            .map { (category: $0, spent: spent[$0] ?? 0, budget: budgetsByCategory[$0]) }
            .sorted { $0.spent > $1.spent }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Spent This Month")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(totalSpent.currencyString)
                        .font(.system(size: 32, weight: .bold))
                    Text("Month is \(Int(BudgetMath.monthElapsedFraction() * 100))% over")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            if rows.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("No spending yet", systemImage: "chart.bar")
                    } description: {
                        Text("Transactions from linked banks land here automatically — or add purchases yourself from the Dashboard. Tap + to set a budget for any category.")
                    }
                }
            } else {
                Section {
                    ForEach(rows, id: \.category) { row in
                        SpendingCategoryRow(category: row.category, spent: row.spent, budget: row.budget)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if let budget = row.budget {
                                    Button(role: .destructive) {
                                        modelContext.delete(budget)
                                    } label: {
                                        Label("Remove Budget", systemImage: "trash")
                                    }
                                }
                            }
                    }
                } header: {
                    Text("By Category")
                } footer: {
                    Text("Swipe a budgeted category to remove its budget. Budgets reset every calendar month.")
                }
            }
        }
        .navigationTitle("Spending & Budgets")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingAddBudget = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddBudget) {
            AddBudgetView()
        }
    }
}

private struct SpendingCategoryRow: View {
    let category: SpendingCategory
    let spent: Decimal
    let budget: Budget?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(category.displayName)
                Spacer()
                if let budget {
                    Text("\(spent.currencyString) of \(budget.monthlyLimit.currencyString)")
                        .foregroundStyle(overLimit ? .red : .secondary)
                        .font(.subheadline)
                } else {
                    Text(spent.currencyString)
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                }
            }
            if let budget, budget.monthlyLimit > 0 {
                ProgressView(value: min(fraction(budget), 1.0))
                    .tint(overLimit ? .red : (fraction(budget) > 0.85 ? .orange : .accentColor))
            }
        }
        .padding(.vertical, 2)
    }

    private var overLimit: Bool {
        guard let budget, budget.monthlyLimit > 0 else { return false }
        return spent > budget.monthlyLimit
    }

    private func fraction(_ budget: Budget) -> Double {
        guard budget.monthlyLimit > 0 else { return 0 }
        return ((spent / budget.monthlyLimit) as NSDecimalNumber).doubleValue
    }
}

private struct AddBudgetView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var budgets: [Budget]

    @State private var category: SpendingCategory = .dining
    @State private var limitText = ""

    /// Only offer spending categories that don't already have a budget.
    private var available: [SpendingCategory] {
        let taken = Set(budgets.map(\.category))
        return SpendingCategory.allCases.filter {
            !taken.contains($0) && !InsightsEngine.nonSpendingCategories.contains($0)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Category", selection: $category) {
                    ForEach(available) { category in
                        Text(category.displayName).tag(category)
                    }
                }
                TextField("Monthly limit", text: $limitText)
                    .keyboardType(.decimalPad)
            }
            .navigationTitle("Add Budget")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        if let limit = Decimal(userInput: limitText), limit > 0 {
                            modelContext.insert(Budget(category: category, monthlyLimit: limit))
                            dismiss()
                        }
                    }
                    .disabled(Decimal(userInput: limitText) == nil)
                }
            }
            .onAppear {
                if let first = available.first { category = first }
            }
        }
    }
}

#Preview {
    NavigationStack { SpendingView() }
        .modelContainer(SampleData.container)
}
