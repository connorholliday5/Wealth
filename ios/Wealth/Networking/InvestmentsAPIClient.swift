import Foundation

/// Read-only investment holdings, fetched live from the Wealth proxy server
/// (server/src/routes/investments.ts → Plaid investmentsHoldingsGet). The app
/// never talks to Plaid directly; the proxy holds the secret. Unlike balances
/// and transactions, holdings are display-on-demand and are NOT persisted in
/// SwiftData — the view fetches them when it appears.
///
/// This mirrors the request/auth pattern in PlaidAPIClient (ServerConfig,
/// x-wealth-key header, checkStatus) but keeps its own tiny GET helper so it
/// stays self-contained.
enum InvestmentsAPIClient {
    static func fetchHoldings(itemId: String) async throws -> PlaidHoldingsResponse {
        try await get(path: "/api/investments/holdings?itemId=\(itemId)")
    }

    // MARK: - Plumbing (duplicated from PlaidAPIClient to stay self-contained)

    private static func get<Response: Decodable>(path: String) async throws -> Response {
        // The path carries a query string, so build the URL directly rather
        // than via appendingPathComponent (which would escape "?").
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
                domain: "InvestmentsAPIClient", code: 401,
                userInfo: [NSLocalizedDescriptionKey: "The server rejected the access key. Check Settings > Server."]
            )
        }
        if !(200...299).contains(http.statusCode) {
            throw NSError(
                domain: "InvestmentsAPIClient", code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "Server error (\(http.statusCode))."]
            )
        }
    }
}

// MARK: - Wire types (raw Plaid JSON shapes, snake_case)

struct PlaidHoldingsResponse: Decodable {
    let holdings: [PlaidHolding]
    let securities: [PlaidSecurity]
}

/// One position: how much of a security is held in a given account. Everything
/// except the two IDs is optional since Plaid's coverage varies by institution.
struct PlaidHolding: Decodable {
    let accountId: String
    let securityId: String
    let quantity: Double?
    let institutionValue: Double?
    let costBasis: Double?

    enum CodingKeys: String, CodingKey {
        case accountId = "account_id"
        case securityId = "security_id"
        case quantity
        case institutionValue = "institution_value"
        case costBasis = "cost_basis"
    }
}

/// Describes a security referenced by a holding, joined via security_id.
struct PlaidSecurity: Decodable {
    let securityId: String
    let name: String?
    let tickerSymbol: String?
    let type: String?

    enum CodingKeys: String, CodingKey {
        case securityId = "security_id"
        case name
        case tickerSymbol = "ticker_symbol"
        case type
    }
}
