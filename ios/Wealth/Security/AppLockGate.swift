import SwiftUI

/// Wraps the app content and shows a lock screen until the user authenticates.
/// Re-locks whenever the app goes to the background, and covers the content the
/// moment the scene stops being active — iOS captures the app-switcher snapshot
/// during the inactive phase, so waiting for .background would leak balances
/// into the switcher thumbnail.
struct AppLockGate<Content: View>: View {
    @AppStorage("appLockEnabled") private var appLockEnabled = true
    @StateObject private var lock = AppLockManager()
    @Environment(\.scenePhase) private var scenePhase
    @ViewBuilder var content: () -> Content

    private var isLockedOut: Bool {
        appLockEnabled && !lock.isUnlocked
    }

    /// Face ID's own system prompt makes the scene inactive, so don't blank the
    /// screen while our authentication is mid-flight.
    private var shouldCover: Bool {
        appLockEnabled && scenePhase != .active && !lock.isAuthenticating
    }

    var body: some View {
        ZStack {
            if isLockedOut {
                LockScreenView(lock: lock)
            } else {
                content()
            }

            if shouldCover {
                PrivacyCurtain()
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isLockedOut)
        .task {
            if appLockEnabled { lock.authenticate() }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                if appLockEnabled { lock.authenticate() }
            case .background:
                lock.lock()
            default:
                break
            }
        }
    }
}

/// Opaque cover shown while the app is inactive (app switcher, notification
/// shade, incoming call) so financial data never appears in snapshots.
private struct PrivacyCurtain: View {
    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
        }
    }
}

struct LockScreenView: View {
    @ObservedObject var lock: AppLockManager

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            Text("Wealth is Locked")
                .font(.title2.bold())
            Text("Authenticate to view your accounts and balances.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            if let error = lock.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Button {
                lock.authenticate()
            } label: {
                Label("Unlock", systemImage: "faceid")
                    .font(.headline)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .disabled(lock.isAuthenticating)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}
