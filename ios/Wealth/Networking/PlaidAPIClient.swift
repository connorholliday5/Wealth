import Foundation

/// Talks to the Wealth proxy server (server/), never to Plaid directly.
/// The proxy holds the Plaid secret; this app only ever sees link tokens and
/// already-resolved account/transaction/liability/investment data.
struct PlaidAPIClient {
    /// Update to your deployed proxy server's URL. localhost works only when
    /// running the iOS Simulator on the same Mac as `npm run dev`.
    static var baseURL = URL(string: "http://localhost:8787")!

    struct ExchangeResponse: Decodable {
        let itemId: String
        let institutionName: String?
    }

    static func createLinkToken() async throws -> String {
        struct Response: Decodable { let linkToken: String }
        let resp: Response = try await post(path: "/api/link/token/create", body: [:] as [String: String])
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

    private static func post<Body: Encodable, Response: Decodable>(path: String, body: Body) async throws -> Response {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(Response.self, from: data)
    }

    private static func get<Response: Decodable>(path: String) async throws -> Response {
        let (data, _) = try await URLSession.shared.data(from: baseURL.appendingPathComponent(path))
        return try JSONDecoder().decode(Response.self, from: data)
    }
}

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
    }

    enum CodingKeys: String, CodingKey {
        case accountId = "account_id"
        case name, type, subtype, balances
    }
}
