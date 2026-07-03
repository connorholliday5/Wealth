import Foundation

/// Where the Wealth server lives and how to authenticate to it. Both values are
/// user-editable in Settings > Server, stored in UserDefaults, and read fresh on
/// every request so changes take effect immediately.
enum ServerConfig {
    static let defaultURLString = "http://localhost:8787"

    static var baseURL: URL {
        let raw = UserDefaults.standard.string(forKey: "serverURL")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !raw.isEmpty, let url = URL(string: raw) {
            return url
        }
        return URL(string: defaultURLString)!
    }

    /// Matches the server's APP_SHARED_SECRET. Empty = header not sent (fine for
    /// a localhost server with no secret configured).
    static var accessKey: String {
        UserDefaults.standard.string(forKey: "serverKey")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    static func request(path: String, method: String = "GET", jsonBody: Data? = nil) -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        if let jsonBody {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = jsonBody
        }
        let key = accessKey
        if !key.isEmpty {
            request.setValue(key, forHTTPHeaderField: "x-wealth-key")
        }
        return request
    }
}
