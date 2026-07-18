import SwiftUI
import SwiftData

/// Edit an existing bill in place — previously the only fix for a wrong
/// amount or date was delete-and-re-add.
struct EditBillView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var accounts: [Account]
    @Bindable var bill: Bill

    @State private var amountText = ""

    var body: some View {
        Form {
            TextField("Name", text: $bill.name)
            HStack {
                TextField("Amount", text: $amountText)
                    .keyboardType(.decimalPad)
                if Decimal(userInput: amountText) == nil {
                    Image(systemName: "exclamationmark.circle")
                        .foregroundStyle(.orange)
                }
            }
            Picker("Type", selection: $bill.kind) {
                ForEach(BillKind.allCases) { kind in
                    Text(kind.displayName).tag(kind)
                }
            }
            Picker("Frequency", selection: $bill.frequency) {
                ForEach(BillFrequency.allCases) { frequency in
                    Text(frequency.displayName).tag(frequency)
                }
            }
            DatePicker("Next due", selection: $bill.nextDueDate, displayedComponents: .date)
            Toggle("Autopay", isOn: $bill.autopay)
            Toggle("Payroll deduction", isOn: $bill.isPayrollDeduction)

            if bill.kind == .loanPayment || bill.kind == .creditCardPayment {
                Picker("Pays down", selection: $bill.linkedAccount) {
                    Text("None").tag(Account?.none)
                    ForEach(accounts.filter { $0.type.isLiability }) { account in
                        Text(account.name).tag(Account?.some(account))
                    }
                }
            }
        }
        .navigationTitle("Edit Bill")
        .onAppear {
            amountText = "\(bill.amount)"
        }
        .onChange(of: amountText) { _, text in
            if let amount = Decimal(userInput: text), amount > 0 {
                bill.amount = amount
            }
        }
        .onChange(of: bill.nextDueDate) { _, newDate in
            // The edited date becomes the new month-day anchor.
            bill.dueDayAnchor = Calendar.current.component(.day, from: newDate)
        }
        .onDisappear {
            NotificationManager.shared.schedule(for: bill)
        }
    }
}
