import SwiftUI
import SwiftData

/// Named savings goals with progress. The paycheck planner allocates toward
/// unfinished goals automatically (dated goals get their required pace first).
struct SavingsGoalsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavingsGoal.createdAt) private var goals: [SavingsGoal]
    @State private var showingAddGoal = false

    var body: some View {
        List {
            if goals.isEmpty {
                ContentUnavailableView {
                    Label("No goals yet", systemImage: "flag.checkered")
                } description: {
                    Text("Saving for a trip, a car, a house down payment? Add a goal and the paycheck planner will budget toward it automatically.")
                }
            }

            ForEach(goals) { goal in
                SavingsGoalRow(goal: goal)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            modelContext.delete(goal)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
        }
        .navigationTitle("Savings Goals")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingAddGoal = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddGoal) {
            AddSavingsGoalView()
        }
    }
}

private struct SavingsGoalRow: View {
    @Bindable var goal: SavingsGoal
    @State private var addAmountText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(goal.name)
                    .font(.headline)
                Spacer()
                if goal.isComplete {
                    Label("Done!", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.subheadline)
                } else {
                    Text("\(goal.savedAmount.currencyString) of \(goal.targetAmount.currencyString)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            ProgressView(value: goal.progressFraction)
                .tint(goal.isComplete ? .green : .accentColor)
            if let targetDate = goal.targetDate, !goal.isComplete {
                HStack {
                    Text("By \(targetDate.formatted(.dateTime.month(.abbreviated).year()))")
                    Spacer()
                    if let monthly = goal.monthlyNeeded() {
                        Text("\(monthly.currencyString)/mo to stay on pace")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            if !goal.isComplete {
                HStack {
                    TextField("Add amount", text: $addAmountText)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                        .font(.subheadline)
                    Button("Add") {
                        if let amount = Decimal(userInput: addAmountText), amount > 0 {
                            goal.savedAmount += amount
                            addAmountText = ""
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(Decimal(userInput: addAmountText) == nil)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct AddSavingsGoalView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var targetText = ""
    @State private var savedText = ""
    @State private var hasTargetDate = false
    @State private var targetDate = Calendar.current.date(byAdding: .month, value: 6, to: .now) ?? .now

    var body: some View {
        NavigationStack {
            Form {
                TextField("Goal name (e.g. Japan Trip)", text: $name)
                TextField("Target amount", text: $targetText)
                    .keyboardType(.decimalPad)
                TextField("Already saved (optional)", text: $savedText)
                    .keyboardType(.decimalPad)
                Toggle("Target date", isOn: $hasTargetDate)
                if hasTargetDate {
                    DatePicker("By", selection: $targetDate, displayedComponents: .date)
                }
            }
            .navigationTitle("New Goal")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .disabled(name.isEmpty || Decimal(userInput: targetText) == nil)
                }
            }
        }
    }

    private func save() {
        guard let target = Decimal(userInput: targetText), target > 0 else { return }
        let goal = SavingsGoal(
            name: name,
            targetAmount: target,
            savedAmount: Decimal(userInput: savedText) ?? 0,
            targetDate: hasTargetDate ? targetDate : nil
        )
        modelContext.insert(goal)
        dismiss()
    }
}

#Preview {
    NavigationStack { SavingsGoalsView() }
        .modelContainer(SampleData.container)
}
