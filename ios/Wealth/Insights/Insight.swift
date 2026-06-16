import Foundation

enum InsightSeverity {
    case success
    case info
    case warning

    var symbolName: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        }
    }
}

struct Insight: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let severity: InsightSeverity
}
