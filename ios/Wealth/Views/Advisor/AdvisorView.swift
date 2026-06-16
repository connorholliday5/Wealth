import SwiftUI
import SwiftData

struct AdvisorView: View {
    @Query private var accounts: [Account]
    @Query private var bills: [Bill]
    @Query private var transactions: [Transaction]

    private var insights: [Insight] {
        InsightsEngine.generate(accounts: accounts, bills: bills, transactions: transactions)
    }

    var body: some View {
        NavigationStack {
            List {
                if insights.isEmpty {
                    ContentUnavailableView(
                        "No insights yet",
                        systemImage: "sparkles",
                        description: Text("Add accounts, bills, and a bit of transaction history and your advisor will start surfacing tips here.")
                    )
                } else {
                    ForEach(insights) { insight in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: insight.severity.symbolName)
                                .foregroundStyle(color(for: insight.severity))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(insight.title)
                                    .font(.headline)
                                Text(insight.message)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Advisor")
        }
    }

    private func color(for severity: InsightSeverity) -> Color {
        switch severity {
        case .success: return .green
        case .info: return .blue
        case .warning: return .orange
        }
    }
}
