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

    /// Keychain account name for the server access key.
    private static let accessKeyAccount = "serverKey"

    /// Matches the server's APP_SHARED_SECRET. Empty = header not sent (fine for
    /// a localhost server with no secret configured). Stored in the Keychain so
    /// the secret never sits in UserDefaults (which lands in device backups).
    static var accessKey: String {
        migrateLegacyKeyIfNeeded()
        return KeychainStore.get(accessKeyAccount)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// Persists the access key to the Keychain. Empty removes it.
    static func setAccessKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        KeychainStore.set(trimmed, for: accessKeyAccount)
    }

    /// One-time silent migration: earlier builds stored the key in UserDefaults.
    /// Move any non-empty value into the Keychain and clear the plaintext copy.
    private static func migrateLegacyKeyIfNeeded() {
        let defaults = UserDefaults.standard
        guard let legacy = defaults.string(forKey: accessKeyAccount)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !legacy.isEmpty else {
            return
        }
        KeychainStore.set(legacy, for: accessKeyAccount)
        defaults.removeObject(forKey: accessKeyAccount)
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
