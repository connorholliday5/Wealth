import SwiftUI
import SwiftData
#if canImport(FoundationModels)
import FoundationModels
#endif

struct AdvisorView: View {
    @Query private var accounts: [Account]
    @Query private var bills: [Bill]
    @Query private var transactions: [Transaction]
    @Query private var budgets: [Budget]
    @AppStorage("advisorProvider") private var providerRaw = AdvisorProvider.auto.rawValue

    private var insights: [Insight] {
        InsightsEngine.generate(accounts: accounts, bills: bills, transactions: transactions, budgets: budgets)
    }

    private var recommendations: [AccountRecommendation] {
        AccountRecommendationEngine.recommend(accounts: accounts, bills: bills, transactions: transactions)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        chatDestination
                    } label: {
                        Label("Chat with Advisor", systemImage: "bubble.left.and.bubble.right.fill")
                    }
                } footer: {
                    Text("Ask free-form questions about your finances. Runs on Apple's on-device model where supported, otherwise a cloud model via your Wealth server. Change this in Settings \u{2192} AI Advisor.")
                }

                Section {
                    NavigationLink {
                        PaycheckPlannerView()
                    } label: {
                        Label("Paycheck Allocation Advisor", systemImage: "dollarsign.arrow.circlepath")
                    }
                } footer: {
                    Text("A priority-waterfall recommendation for where each paycheck should go, computed from your accounts and bills.")
                }

                if !recommendations.isEmpty {
                    Section {
                        ForEach(recommendations) { recommendation in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: recommendation.symbolName)
                                    .foregroundStyle(.tint)
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(recommendation.title)
                                        .font(.headline)
                                    Text(recommendation.reason)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    } header: {
                        Text("Accounts Worth Opening")
                    } footer: {
                        Text("Based only on which account types you're missing — general guidance, not personalized financial advice.")
                    }
                }

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

    /// Routes to the on-device or cloud chat based on the user's preference,
    /// what the device supports, and whether the app was even built with a
    /// toolchain that has FoundationModels (older Xcode versions don't).
    @ViewBuilder private var chatDestination: some View {
        #if canImport(FoundationModels)
        switch AdvisorProvider(rawValue: providerRaw) ?? .auto {
        case .cloud:
            CloudChatView()
        case .onDevice:
            if #available(iOS 26.0, *) {
                AIChatView()
            } else {
                CloudChatView()
            }
        case .auto:
            if #available(iOS 26.0, *), case .available = SystemLanguageModel.default.availability {
                AIChatView()
            } else {
                CloudChatView()
            }
        }
        #else
        CloudChatView()
        #endif
    }

    private func color(for severity: InsightSeverity) -> Color {
        switch severity {
        case .success: return .green
        case .info: return .blue
        case .warning: return .orange
        }
    }
}
