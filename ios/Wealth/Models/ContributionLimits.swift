import Foundation

/// IRS contribution limits change annually; these are sane starting defaults
/// the user can override per-account from the account detail screen.
enum ContributionLimits {
    static func defaultAnnualLimit(for type: AccountType, year: Int = Calendar.current.component(.year, from: .now)) -> Decimal? {
        switch type {
        case .rothIRA, .traditionalIRA:
            return 7_000
        case .fourOhOneK:
            return 23_500
        case .hsa:
            return 4_300 // individual coverage; family coverage is roughly double
        default:
            return nil
        }
    }
}
