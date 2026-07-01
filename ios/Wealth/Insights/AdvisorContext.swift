import Foundation

/// One line in an advisor conversation. Shared by the on-device (Apple
/// Foundation Models) and cloud (server-proxied) chat backends so the UI and
/// the system prompt are identical regardless of which model answers.
struct AdvisorMessage: Identifiable, Equatable {
    let id = UUID()
    let role: Role
    var text: String
    enum Role: String { case user, advisor }
}

/// Which model answers the conversational advisor.
enum AdvisorProvider: String, CaseIterable, Identifiable {
    /// Use the on-device model if available, otherwise fall back to cloud.
    case auto
    /// Apple Foundation Models, on-device (iOS 26+, Apple Intelligence devices).
    case onDevice
    /// A cloud model reached through the Wealth server.
    case cloud

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: return "Automatic"
        case .onDevice: return "On-Device (Apple Intelligence)"
        case .cloud: return "Cloud"
        }
    }
}

/// Builds the system prompt that grounds either advisor backend in the user's
/// own data. Nothing here is model-specific — it's the same context whether the
/// prompt is fed to Apple's on-device model or sent to the cloud model via the
/// Wealth server.
func buildAdvisorSystemPrompt(accounts: [Account], bills: [Bill]) -> String {
    let netWorth = accounts.reduce(Decimal(0)) { $0 + $1.netWorthContribution }

    let accountLines = accounts.map { account -> String in
        let label = account.type.isLiability ? "owes" : "has"
        var line = "- \(account.name) (\(account.type.displayName)) \(label) \(account.balance.currencyString)"
        if let rate = account.interestRate ?? account.apr { line += ", \(rate)% APR" }
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
