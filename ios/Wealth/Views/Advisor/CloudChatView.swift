import SwiftUI
import SwiftData

/// Cloud advisor chat — works on any iPhone, routed through the Wealth server.
/// This is the conversational advisor for devices without Apple Intelligence.
struct CloudChatView: View {
    @Query private var accounts: [Account]
    @Query private var bills: [Bill]
    @StateObject private var advisor = CloudAdvisorManager()
    @State private var input = ""
    @State private var available: Bool?

    var body: some View {
        Group {
            switch available {
            case .none:
                ProgressView("Checking advisor…")
            case .some(true):
                ChatScaffold(
                    messages: advisor.messages,
                    isResponding: advisor.isResponding,
                    input: $input
                ) { text in
                    Task { await advisor.send(text) }
                }
            case .some(false):
                ContentUnavailableView(
                    "Cloud Advisor Not Configured",
                    systemImage: "cloud",
                    description: Text("Add an ANTHROPIC_API_KEY to your Wealth server and make sure the app points at it (PlaidAPIClient.baseURL) to enable the cloud advisor.")
                )
            }
        }
        .navigationTitle("Cloud Advisor")
        .task {
            advisor.start(accounts: accounts, bills: bills)
            available = await AdvisorAPIClient.isAvailable()
        }
    }
}
