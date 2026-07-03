import XCTest
import Foundation
import SwiftData
@testable import Wealth

/// Shared helpers for the unit tests: an in-memory SwiftData context (so @Model
/// instances behave exactly as they do in the app) and Decimal comparison.
@MainActor
enum TestSupport {
    static func makeContext() throws -> ModelContext {
        let schema = Schema([Account.self, Transaction.self, Bill.self, NetWorthSnapshot.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    static func daysFromNow(_ days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: .now) ?? .now
    }
}

extension XCTestCase {
    /// Decimal equality via Double bridge — tolerant of the tiny rounding that
    /// Bill.monthlyEquivalent introduces (occurrencesPerYear is a Double).
    func assertDecimalEqual(
        _ a: Decimal,
        _ b: Decimal,
        accuracy: Double = 0.0001,
        _ message: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            NSDecimalNumber(decimal: a).doubleValue,
            NSDecimalNumber(decimal: b).doubleValue,
            accuracy: accuracy,
            message,
            file: file,
            line: line
        )
    }
}
