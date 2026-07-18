import Foundation

/// IRS contribution limits, per tax year. The user can still override
/// per-account from the account detail screen (e.g. catch-up contributions,
/// family-coverage HSA); the override should be reserved for those cases —
/// accounts without an override automatically track the current year here.
enum ContributionLimits {
    /// Known limits by tax year. When a year isn't listed yet (the IRS
    /// announces each fall), the latest known year's values are used.
    private static let limitsByYear: [Int: (ira: Decimal, fourOhOneK: Decimal, hsaIndividual: Decimal)] = [
        2025: (ira: 7_000, fourOhOneK: 23_500, hsaIndividual: 4_300),
        2026: (ira: 7_500, fourOhOneK: 24_500, hsaIndividual: 4_400),
    ]

    static func defaultAnnualLimit(for type: AccountType, year: Int = Calendar.current.component(.year, from: .now)) -> Decimal? {
        let table = limitsByYear[year]
            ?? limitsByYear[limitsByYear.keys.max() ?? 2026]
        guard let table else { return nil }
        switch type {
        case .rothIRA, .traditionalIRA:
            return table.ira
        case .fourOhOneK:
            return table.fourOhOneK
        case .hsa:
            return table.hsaIndividual // individual coverage; family is roughly double — use the per-account override
        default:
            return nil
        }
    }
}
