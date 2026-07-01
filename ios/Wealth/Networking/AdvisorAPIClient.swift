import Foundation

/// Talks to the Wealth server's cloud-advisor route. The server holds the model
/// API key and makes the call; the app only ever sends the conversation (with a
/// system prompt built from local data) and receives the reply text. This is the
/// advisor path for iPhones without Apple Intelligence.
enum AdvisorAPIClient {
    /// Reuses the same base URL as the Plaid proxy — it's the same server.
    static var baseURL: URL { PlaidAPIClient.baseURL }

    struct WireMessage: Codable {
        let role: String   // "user" or "advisor"
        let content: String
    }

    static func isAvailable() async -> Bool {
        struct Response: Decodable { let available: Bool }
        do {
            let (data, _) = try await URLSession.shared.data(from: baseURL.appendingPathComponent("/api/advisor/available"))
            return (try? JSONDecoder().decode(Response.self, from: data))?.available ?? false
        } catch {
            return false
        }
    }

    static func chat(system: String, messages: [WireMessage]) async throws -> String {
        struct Request: Encodable {
            let system: String
            let messages: [WireMessage]
        }
        struct Response: Decodable {
            let reply: String?
            let error: String?
        }

        var request = URLRequest(url: baseURL.appendingPathComponent("/api/advisor/chat"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(Request(system: system, messages: messages))

        let (data, _) = try await URLSession.shared.data(for: request)
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        if let reply = decoded.reply { return reply }
        throw NSError(
            domain: "AdvisorAPIClient",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: decoded.error ?? "The advisor couldn't respond."]
        )
    }
}
