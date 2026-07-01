import Foundation
import LocalAuthentication

/// Gates the app behind Face ID / Touch ID / device passcode using LocalAuthentication.
/// Uses `.deviceOwnerAuthentication` so it falls back to the passcode when biometrics
/// aren't available, and never locks out a device that has no passcode set at all.
@MainActor
final class AppLockManager: ObservableObject {
    @Published var isUnlocked = false
    @Published var lastError: String?
    @Published private(set) var isAuthenticating = false

    /// Whether the device can evaluate biometrics or a passcode at all.
    var canUseAuthentication: Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }

    func authenticate(reason: String = "Unlock to view your finances") {
        guard !isAuthenticating, !isUnlocked else { return }

        let context = LAContext()
        context.localizedFallbackTitle = "Enter Passcode"

        var policyError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &policyError) else {
            // No biometrics/passcode configured — don't lock the user out of their own app.
            isUnlocked = true
            return
        }

        isAuthenticating = true
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, evalError in
            Task { @MainActor in
                self.isAuthenticating = false
                if success {
                    self.isUnlocked = true
                    self.lastError = nil
                } else {
                    self.isUnlocked = false
                    self.lastError = evalError?.localizedDescription
                }
            }
        }
    }

    func lock() {
        isUnlocked = false
    }
}
