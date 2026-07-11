// This whole file compiles only when the SDK ships Apple's FoundationModels
// framework (Xcode 26+ / iOS 26 SDK). On older Xcode versions the app builds
// without on-device chat and AdvisorView routes to the cloud advisor instead.
#if canImport(FoundationModels)

import Foundation
import FoundationModels

/// Wraps Apple's on-device Foundation Models framework (iOS 26+, Apple Intelligence
/// devices only) to provide free-form Q&A on top of your local financial data.
/// Nothing here ever leaves the device — there's no network call, no API key,
/// and no cost. It's a companion to InsightsEngine, not a replacement: the rules
/// engine still drives the deterministic insights on the Advisor tab.
@available(iOS 26.0, *)
@MainActor
final class AIAdvisorManager: ObservableObject {
    @Published var messages: [AdvisorMessage] = []
    @Published var isResponding = false
    @Published var availability: SystemLanguageModel.Availability = SystemLanguageModel.default.availability

    private var session: LanguageModelSession?

    func start(accounts: [Account], bills: [Bill]) {
        availability = SystemLanguageModel.default.availability
        guard case .available = availability else { return }
        guard session == nil else { return }
        session = LanguageModelSession(instructions: buildAdvisorSystemPrompt(accounts: accounts, bills: bills))
        messages = [AdvisorMessage(role: .advisor, text: "I've loaded a snapshot of your accounts and bills. Ask me anything — e.g. \"Should I pay off my car loan or invest extra cash?\"")]
    }

    func send(_ text: String) async {
        guard let session, !text.isEmpty else { return }
        messages.append(AdvisorMessage(role: .user, text: text))
        isResponding = true
        defer { isResponding = false }
        do {
            let response = try await session.respond(to: text)
            messages.append(AdvisorMessage(role: .advisor, text: response.content))
        } catch {
            messages.append(AdvisorMessage(role: .advisor, text: "Sorry, I couldn't process that: \(error.localizedDescription)"))
        }
    }
}

#endif
