import Foundation

/// Drives a cloud-model chat through the Wealth server. Works on any iPhone
/// (no Apple Intelligence required). Financial context is built locally and sent
/// as the system prompt; the server holds the API key and makes the call.
///
/// Note: unlike the on-device advisor, using this sends a snapshot of your
/// accounts/bills to the cloud model (via your own server) with each message.
@MainActor
final class CloudAdvisorManager: ObservableObject {
    @Published var messages: [AdvisorMessage] = []
    @Published var isResponding = false
    @Published var errorMessage: String?

    private var systemPrompt = ""

    func start(accounts: [Account], bills: [Bill]) {
        guard systemPrompt.isEmpty else { return }
        systemPrompt = buildAdvisorSystemPrompt(accounts: accounts, bills: bills)
    }

    func send(_ text: String) async {
        guard !text.isEmpty else { return }
        messages.append(AdvisorMessage(role: .user, text: text))
        isResponding = true
        errorMessage = nil
        defer { isResponding = false }

        // Only real turns go to the model — no synthetic greeting — so the
        // transcript alternates correctly starting from the user.
        let wire = messages.map { AdvisorAPIClient.WireMessage(role: $0.role.rawValue, content: $0.text) }
        do {
            let reply = try await AdvisorAPIClient.chat(system: systemPrompt, messages: wire)
            messages.append(AdvisorMessage(role: .advisor, text: reply))
        } catch {
            errorMessage = error.localizedDescription
            messages.append(AdvisorMessage(role: .advisor, text: "Sorry, I couldn't reach the advisor: \(error.localizedDescription)"))
        }
    }
}
