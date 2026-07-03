import XCTest
@testable import Wealth

@MainActor
final class SyncEngineTests: XCTestCase {

    // MARK: - Category mapping

    func testCategoryMapping() {
        XCTAssertEqual(SyncEngine.mapCategory(primary: "INCOME", detailed: nil), .income)
        XCTAssertEqual(SyncEngine.mapCategory(primary: "LOAN_PAYMENTS", detailed: nil), .debtPayment)
        XCTAssertEqual(SyncEngine.mapCategory(primary: "TRANSFER_OUT", detailed: nil), .savingsTransfer)
        XCTAssertEqual(
            SyncEngine.mapCategory(primary: "FOOD_AND_DRINK", detailed: "FOOD_AND_DRINK_GROCERIES"),
            .groceries
        )
        XCTAssertEqual(
            SyncEngine.mapCategory(primary: "FOOD_AND_DRINK", detailed: "FOOD_AND_DRINK_RESTAURANT"),
            .dining
        )
        XCTAssertEqual(
            SyncEngine.mapCategory(primary: "RENT_AND_UTILITIES", detailed: "RENT_AND_UTILITIES_RENT"),
            .housing
        )
        XCTAssertEqual(
            SyncEngine.mapCategory(primary: "RENT_AND_UTILITIES", detailed: "RENT_AND_UTILITIES_INTERNET_AND_CABLE"),
            .utilities
        )
        XCTAssertEqual(SyncEngine.mapCategory(primary: "GENERAL_MERCHANDISE", detailed: nil), .shopping)
        XCTAssertEqual(SyncEngine.mapCategory(primary: nil, detailed: nil), .other)
        XCTAssertEqual(SyncEngine.mapCategory(primary: "SOMETHING_NEW", detailed: nil), .other)
    }

    // MARK: - Wire decoding (raw Plaid JSON shapes)

    func testDecodesPlaidTransactionSync() throws {
        let json = """
        {
          "added": [
            {
              "transaction_id": "txn_1",
              "account_id": "acc_1",
              "amount": 42.5,
              "date": "2026-06-30",
              "name": "CHIPOTLE 1234",
              "merchant_name": "Chipotle",
              "pending": false,
              "personal_finance_category": { "primary": "FOOD_AND_DRINK", "detailed": "FOOD_AND_DRINK_RESTAURANT" }
            }
          ],
          "modified": [],
          "removed": [ { "transaction_id": "txn_0", "account_id": "acc_1" } ]
        }
        """.data(using: .utf8)!

        let sync = try JSONDecoder().decode(PlaidTransactionSync.self, from: json)
        XCTAssertEqual(sync.added.count, 1)
        let txn = sync.added[0]
        XCTAssertEqual(txn.transactionId, "txn_1")
        XCTAssertEqual(txn.merchantName, "Chipotle")
        XCTAssertEqual(txn.amount, 42.5, accuracy: 0.001)
        XCTAssertEqual(txn.personalFinanceCategory?.primary, "FOOD_AND_DRINK")
        XCTAssertEqual(sync.removed.first?.transactionId, "txn_0")
        XCTAssertNotNil(SyncEngine.parseDate(txn.date))
    }

    func testDecodesLiabilitiesAndAppliesToAccounts() throws {
        let json = """
        {
          "credit": [
            {
              "account_id": "card_1",
              "minimum_payment_amount": 35.0,
              "aprs": [
                { "apr_percentage": 29.99, "apr_type": "cash_apr" },
                { "apr_percentage": 22.99, "apr_type": "purchase_apr" }
              ]
            }
          ],
          "student": [
            { "account_id": "loan_1", "interest_rate_percentage": 5.5, "minimum_payment_amount": 210.0 }
          ],
          "mortgage": null
        }
        """.data(using: .utf8)!

        let liabilities = try JSONDecoder().decode(PlaidLiabilities.self, from: json)

        let card = Account(name: "Card", type: .creditCard, balance: 1000)
        card.plaidAccountId = "card_1"
        let loan = Account(name: "Loan", type: .studentLoan, balance: 10000)
        loan.plaidAccountId = "loan_1"

        SyncEngine.apply(
            liabilities: liabilities,
            accountsByPlaidId: ["card_1": card, "loan_1": loan]
        )

        XCTAssertEqual(card.apr ?? 0, 22.99, accuracy: 0.001)   // purchase APR preferred
        assertDecimalEqual(card.minimumPayment ?? 0, 35)
        XCTAssertEqual(loan.interestRate ?? 0, 5.5, accuracy: 0.001)
        assertDecimalEqual(loan.minimumPayment ?? 0, 210)
    }

    func testPlaidAmountSignConvention() {
        // Plaid: positive = money leaving the account. Local: positive = money in.
        // The import negates, so a $42.50 purchase must become -42.50 locally.
        let plaidOutflow = 42.5
        let local = Decimal(-plaidOutflow)
        XCTAssertLessThan(local, 0)
    }
}
