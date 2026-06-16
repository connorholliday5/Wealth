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
    struct ChatMessage: Identifiable {
        let id = UUID()
        let role: Role
        var text: String
        enum Role { case user, advisor }
    }

    @Published var messages: [ChatMessage] = []
    @Published var isResponding = false
    @Published var availability: SystemLanguageModel.Availability = SystemLanguageModel.default.availability

    private var session: LanguageModelSession?

    func start(accounts: [Account], bills: [Bill]) {
        availability = SystemLanguageModel.default.availability
        guard case .available = availability else { return }
        guard session == nil else { return }
        session = LanguageModelSession(instructions: Self.buildInstructions(accounts: accounts, bills: bills))
        messages = [ChatMessage(role: .advisor, text: "I've loaded a snapshot of your accounts and bills. Ask me anything — e.g. \"Should I pay off my car loan or invest extra cash?\"")]
    }

    func send(_ text: String) async {
        guard let session, !text.isEmpty else { return }
        messages.append(ChatMessage(role: .user, text: text))
        isResponding = true
        defer { isResponding = false }
        do {
            let response = try await session.respond(to: text)
            messages.append(ChatMessage(role: .advisor, text: response.content))
        } catch {
            messages.append(ChatMessage(role: .advisor, text: "Sorry, I couldn't process that: \(error.localizedDescription)"))
        }
    }

    private static func buildInstructions(accounts: [Account], bills: [Bill]) -> String {
        let netWorth = accounts.reduce(Decimal(0)) { $0 + $1.netWorthContribution }

        let accountLines = accounts.map { account -> String in
            let label = account.type.isLiability ? "owes" : "has"
            var line = "- \(account.name) (\(account.type.displayName)) \(label) \(account.balance.currencyString)"
            if let rate = account.interestRate { line += ", \(rate)% APR" }
            if let limit = account.contributionLimitOverride ?? ContributionLimits.defaultAnnualLimit(for: account.type) {
                let contributed = account.yearToDateContribution ?? 0
                line += ", contributed \(contributed.currencyString) of \(limit.currencyString) this year"
            }
            return line
        }.joined(separator: "\n")

        let billLines = bills.prefix(25).map { bill in
            "- \(bill.name): \(bill.amount.currencyString) due \(bill.frequency.displayName.lowercased()), next due \(bill.nextDueDate.formatted(date: .abbreviated, time: .omitted))"
        }.joined(separator: "\n")

        return """
        You are a personal financial assistant embedded in the user's own finance-tracking app. \
        You are talking directly to the account owner about their own real numbers below. \
        Be concise, specific, and reference their actual balances/rates/due dates rather than generic advice. \
        You are not a licensed financial, tax, or legal advisor — for complex tax, legal, or large investment \
        decisions, remind the user to consult a licensed professional. Never guarantee investment returns.

        Current net worth: \(netWorth.currencyString)

        Accounts:
        \(accountLines)

        Upcoming bills:
        \(billLines)
        """
    }
}
