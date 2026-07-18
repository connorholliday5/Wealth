import Foundation

/// A suggestion to open (or better use) a type of account, with the reasoning
/// spelled out. Deterministic and computed locally — no AI, no network.
struct AccountRecommendation: Identifiable {
    let id = UUID()
    let title: String
    let reason: String
    let symbolName: String
}

/// Rules for "which accounts should I have?" — the classic priority ladder:
/// employer match → emergency fund in a savings account → Roth IRA → HSA →
/// put idle cash to work. Each rule only fires when the user's actual data
/// shows the gap, and each explains itself in plain language.
enum AccountRecommendationEngine {
    static func recommend(
        accounts: [Account],
        bills: [Bill],
        transactions: [Transaction],
        asOf now: Date = .now
    ) -> [AccountRecommendation] {
        var recommendations: [AccountRecommendation] = []
        let year = Calendar.current.component(.year, from: now)

        let hasSavings = accounts.contains { $0.type == .savings }
        let hasIRA = accounts.contains { $0.type == .rothIRA || $0.type == .traditionalIRA }
        let hasHSA = accounts.contains { $0.type == .hsa }
        let has401k = accounts.contains { $0.type == .fourOhOneK }
        let checking = accounts.filter { $0.type == .checking }.reduce(Decimal(0)) { $0 + $1.balance }
        let monthlyCosts = FinanceMath.monthlyLivingCosts(bills: bills, transactions: transactions, asOf: now)
        let efTarget = monthlyCosts * 3

        // 1. A 401(k) — conditional, since we can't see the employer's benefits.
        if !has401k {
            recommendations.append(AccountRecommendation(
                title: "Employer 401(k) — if offered, enroll",
                reason: "You don't have a 401(k) tracked here. If your employer offers one — especially with a match — enroll at least up to the full match before other investing. A match is an instant 50-100% return on those dollars.",
                symbolName: "building.2"
            ))
        }

        // 2. A dedicated savings account for the emergency fund.
        if !hasSavings {
            recommendations.append(AccountRecommendation(
                title: "Open a high-yield savings account",
                reason: monthlyCosts > 0
                    ? "You have no savings account for an emergency fund. A high-yield savings account (many pay ~4% APY) is the right home for your 3-6 month cushion — about \(efTarget.currencyString) based on your bills and spending."
                    : "You have no savings account for an emergency fund. A high-yield savings account (many pay ~4% APY) keeps your cushion separate from spending money and earns real interest.",
                symbolName: "shield.lefthalf.filled"
            ))
        }

        // 3. Roth IRA — the classic next step once the match is captured.
        if !hasIRA {
            let limit = ContributionLimits.defaultAnnualLimit(for: .rothIRA, year: year) ?? 0
            recommendations.append(AccountRecommendation(
                title: "Open a Roth IRA",
                reason: "You have no IRA. A Roth IRA lets up to \(limit.currencyString)/year (\(String(year)) limit) grow completely tax-free — you can withdraw contributions anytime, and early-career years are usually the best time since your tax rate is lower now than in retirement. High earners should check the income limits or use the backdoor route.",
                symbolName: "leaf"
            ))
        }

        // 4. HSA — conditional on the health plan we can't see.
        if !hasHSA {
            let limit = ContributionLimits.defaultAnnualLimit(for: .hsa, year: year) ?? 0
            recommendations.append(AccountRecommendation(
                title: "HSA — if you're on a high-deductible health plan",
                reason: "No HSA tracked. If your health insurance is a high-deductible plan, an HSA is the only triple-tax-free account (deductible going in, grows tax-free, tax-free for medical costs) — up to \(limit.currencyString)/year for individual coverage.",
                symbolName: "cross.case"
            ))
        }

        // 5. Idle cash: checking far beyond the emergency target earns ~nothing.
        if hasSavings, efTarget > 0, checking > efTarget {
            let idle = checking - efTarget
            recommendations.append(AccountRecommendation(
                title: "Put idle checking cash to work",
                reason: "Your checking balance (\(checking.currencyString)) is well above what near-term bills need. Roughly \(idle.currencyString) could earn ~4% in high-yield savings or go toward retirement room instead of sitting at ~0%.",
                symbolName: "arrow.up.right.circle"
            ))
        }

        return recommendations
    }
}
