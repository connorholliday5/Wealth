import SwiftUI
import SwiftData

struct AddBillView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var accounts: [Account]

    @State private var name = ""
    @State private var amountText = ""
    @State private var kind: BillKind = .utility
    @State private var frequency: BillFrequency = .monthly
    @State private var nextDueDate = Date.now
    @State private var autopay = false
    @State private var isPayrollDeduction = false
    @State private var linkedAccount: Account?

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                TextField("Amount", text: $amountText)
                    .keyboardType(.decimalPad)
                Picker("Type", selection: $kind) {
                    ForEach(BillKind.allCases) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                Picker("Frequency", selection: $frequency) {
                    ForEach(BillFrequency.allCases) { frequency in
                        Text(frequency.displayName).tag(frequency)
                    }
                }
                DatePicker("Next due", selection: $nextDueDate, displayedComponents: .date)
                Toggle("Autopay", isOn: $autopay)
                Toggle("Payroll deduction", isOn: $isPayrollDeduction)

                if kind == .loanPayment || kind == .creditCardPayment {
                    Picker("Pays down", selection: $linkedAccount) {
                        Text("None").tag(Account?.none)
                        ForEach(accounts.filter { $0.type.isLiability }) { account in
                            Text(account.name).tag(Account?.some(account))
                        }
                    }
                }
            }
            .navigationTitle("Add Bill")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .disabled(name.isEmpty || amountText.isEmpty)
                }
            }
        }
    }

    private func save() {
        guard let amount = Decimal(string: amountText) else { return }
        let bill = Bill(
            name: name,
            amount: amount,
            kind: kind,
            frequency: frequency,
            nextDueDate: nextDueDate,
            autopay: autopay,
            isPayrollDeduction: isPayrollDeduction,
            linkedAccount: linkedAccount
        )
        modelContext.insert(bill)
        dismiss()
    }
}
