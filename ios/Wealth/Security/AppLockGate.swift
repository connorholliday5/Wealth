import SwiftUI

/// Wraps the app content and shows a lock screen until the user authenticates.
/// Re-locks whenever the app goes to the background so balances aren't left
/// exposed in the app switcher or on return.
struct AppLockGate<Content: View>: View {
    @AppStorage("appLockEnabled") private var appLockEnabled = true
    @StateObject private var lock = AppLockManager()
    @Environment(\.scenePhase) private var scenePhase
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            if !appLockEnabled || lock.isUnlocked {
                content()
            } else {
                LockScreenView(lock: lock)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut, value: lock.isUnlocked)
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
