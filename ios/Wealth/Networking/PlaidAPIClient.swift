import Foundation

/// Talks to the Wealth proxy server (server/), never to Plaid directly.
/// The proxy holds the Plaid secret; this app only ever sees link tokens and
/// already-resolved account/transaction/liability data. Server address and
/// access key come from Settings > Server (see ServerConfig).
enum PlaidAPIClient {
    /// Kept for call sites that only need the address (e.g. advisor client).
    static var baseURL: URL { ServerConfig.baseURL }

    struct ExchangeResponse: Decodable {
        let itemId: String
        let institutionName: String?
    }

    static func createLinkToken() async throws -> String {
        struct Response: Decodable { let linkToken: String }
        let resp: Response = try await post(path: "/api/link/token/create", body: [String: String]())
        return resp.linkToken
    }

    static func exchangePublicToken(_ publicToken: String) async throws -> ExchangeResponse {
        try await post(path: "/api/link/token/exchange", body: ["publicToken": publicToken])
    }

    static func fetchAccounts() async throws -> [LinkedItemAccounts] {
        struct Response: Decodable { let items: [LinkedItemAccounts] }
        let resp: Response = try await get(path: "/api/accounts")
        return resp.items
    }

    /// Incremental transaction sync for one linked institution. Pass
    /// restart=true to pull full history again (fresh install).
    static func syncTransactions(itemId: String, restart: Bool) async throws -> PlaidTransactionSync {
        var path = "/api/transactions/sync?itemId=\(itemId)"
        if restart { path += "&restart=1" }
        return try await get(path: path)
    }

    /// Credit-card APRs and loan terms for one linked institution.
    static func fetchLiabilities(itemId: String) async throws -> PlaidLiabilities {
        try await get(path: "/api/liabilities?itemId=\(itemId)")
    }

    /// Disconnects an institution: the server revokes the Plaid item and
    /// deletes its stored token/cursor. Called when the user deletes the last
    /// local account of that institution.
    static func removeItem(itemId: String) async throws {
        let request = ServerConfig.request(path: "/api/link/item/\(itemId)", method: "DELETE")
        let (_, response) = try await URLSession.shared.data(for: request)
        try Self.checkStatus(response)
    }

    // MARK: - Plumbing

    private static func post<Body: Encodable, Response: Decodable>(path: String, body: Body) async throws -> Response {
        let request = ServerConfig.request(path: path, method: "POST", jsonBody: try JSONEncoder().encode(body))
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.checkStatus(response)
        return try JSONDecoder().decode(Response.self, from: data)
    }

    private static func get<Response: Decodable>(path: String) async throws -> Response {
        // The path may contain a query string, so build the URL directly
        // rather than via appendingPathComponent (which escapes "?").
        guard let url = URL(string: ServerConfig.baseURL.absoluteString + path) else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        let key = ServerConfig.accessKey
        if !key.isEmpty {
            request.setValue(key, forHTTPHeaderField: "x-wealth-key")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.checkStatus(response)
        return try JSONDecoder().decode(Response.self, from: data)
    }

    private static func checkStatus(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        if http.statusCode == 401 {
            throw NSError(
                domain: "PlaidAPIClient", code: 401,
                userInfo: [NSLocalizedDescriptionKey: "The server rejected the access key. Check Settings > Server."]
            )
        }
        if !(200...299).contains(http.statusCode) {
            throw NSError(
                domain: "PlaidAPIClient", code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "Server error (\(http.statusCode))."]
            )
        }
    }
}

// MARK: - Wire types (raw Plaid JSON shapes, snake_case)

struct LinkedItemAccounts: Decodable {
    let itemId: String
    let institutionName: String?
    let accounts: [PlaidAccount]
}

struct PlaidAccount: Decodable {
    let accountId: String
    let name: String
    let type: String
    let subtype: String?
    let balances: Balances

    struct Balances: Decodable {
        let current: Double?
        let available: Double?
        /// Credit limit for cards — powers the utilization insight.
        let limit: Double?
    }

    enum CodingKeys: String, CodingKey {
        case accountId = "account_id"
        case name, type, subtype, balances
    }
}

struct PlaidTransactionSync: Decodable {
    let added: [PlaidTransaction]
    let modified: [PlaidTransaction]
    let removed: [PlaidRemovedTransaction]
}

/// Note: Plaid's `amount` is positive for money LEAVING the account; the app's
/// Transaction model uses positive = money in. SyncEngine negates on import.
struct PlaidTransaction: Decodable {
    let transactionId: String
    let accountId: String
    let amount: Double
    let date: String            // "yyyy-MM-dd"
    let name: String?
    let merchantName: String?
    let pending: Bool?
    let personalFinanceCategory: PFC?

    struct PFC: Decodable {
        let primary: String?
        let detailed: String?
    }

    enum CodingKeys: String, CodingKey {
        case transactionId = "transaction_id"
        case accountId = "account_id"
        case amount, date, name, pending
        case merchantName = "merchant_name"
        case personalFinanceCategory = "personal_finance_category"
    }
}

struct PlaidRemovedTransaction: Decodable {
    let transactionId: String

    enum CodingKeys: String, CodingKey {
        case transactionId = "transaction_id"
    }
}

/// Liabilities payload — every field optional since coverage varies by bank.
struct PlaidLiabilities: Decodable {
    let credit: [Credit]?
    let student: [Student]?
    let mortgage: [Mortgage]?

    struct Credit: Decodable {
        let accountId: String?
        let aprs: [APR]?
        let minimumPaymentAmount: Double?

        struct APR: Decodable {
            let aprPercentage: Double?
            let aprType: String?

            enum CodingKeys: String, CodingKey {
                case aprPercentage = "apr_percentage"
                case aprType = "apr_type"
            }
        }

        enum CodingKeys: String, CodingKey {
            case accountId = "account_id"
            case aprs
            case minimumPaymentAmount = "minimum_payment_amount"
        }
    }

    struct Student: Decodable {
        let accountId: String?
        let interestRatePercentage: Double?
        let minimumPaymentAmount: Double?

        enum CodingKeys: String, CodingKey {
            case accountId = "account_id"
            case interestRatePercentage = "interest_rate_percentage"
            case minimumPaymentAmount = "minimum_payment_amount"
        }
    }

    struct Mortgage: Decodable {
        let accountId: String?
        let interestRate: Rate?
        let nextMonthlyPayment: Double?

        struct Rate: Decodable {
            let percentage: Double?
        }

        enum CodingKeys: String, CodingKey {
            case accountId = "account_id"
            case interestRate = "interest_rate"
            case nextMonthlyPayment = "next_monthly_payment"
        }
    }
}
