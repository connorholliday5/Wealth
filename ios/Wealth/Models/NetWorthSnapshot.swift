import Foundation
import SwiftData

/// One point of net-worth history, recorded at most once per day by
/// MaintenanceEngine so the Dashboard can chart the trend over time.
@Model
final class NetWorthSnapshot {
    var date: Date
    var value: Decimal

    init(date: Date, value: Decimal) {
        self.date = date
        self.value = value
    }
}
