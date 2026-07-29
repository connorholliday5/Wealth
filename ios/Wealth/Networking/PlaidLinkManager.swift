import SwiftUI
import SwiftData
import UIKit
import LinkKit

/// Drives the Plaid Link UI. Account creation itself is delegated to
/// `SyncEngine.importNewAccounts` so linking and syncing share one code path
/// (and can never create duplicates). Requires the proxy server (see server/)
/// to be running and reachable at `ServerConfig.baseURL`.
@MainActor
final class PlaidLinkManager: ObservableObject {
    /// Flips true once a link finished AND its accounts landed locally.
    @Published var didLinkAccounts = false
    @Published var isFinishingLink = false
    @Published var errorMessage: String?

    private var handler: Handler?
    private var modelContext: ModelContext?

    func presentLink(context: ModelContext) {
        modelContext = context
        Task {
            do {
                let linkToken = try await PlaidAPIClient.createLinkToken()
                openLink(linkToken: linkToken)
            } catch {
                errorMessage = "Couldn't start Plaid Link: \(error.localizedDescription). Is the proxy server running?"
            }
        }
    }

    /// Reopens Plaid Link in update mode to repair a broken connection. Unlike
    /// presentLink(), there's no public-token exchange and no accounts are
    /// created — the item is repaired at Plaid and the next sync succeeds.
    func presentRelink(itemId: String) {
        Task {
            do {
                let linkToken = try await PlaidAPIClient.createUpdateLinkToken(itemId: itemId)
                openRelink(linkToken: linkToken)
            } catch {
                errorMessage = "Couldn't start reconnect: \(error.localizedDescription). Is the proxy server running?"
            }
        }
    }

    private func openRelink(linkToken: String) {
        var configuration = LinkTokenConfiguration(token: linkToken) { [weak self] _ in
            // Update mode succeeded: connection repaired at Plaid. Nothing to
            // exchange or create — just clear any prior error. The next balance
            // sync will fetch and drop this item from itemsNeedingRelink.
            self?.errorMessage = nil
        }
        configuration.onExit = { [weak self] exit in
            if let error = exit.error {
                self?.errorMessage = "Reconnect didn't finish: \(String(describing: error))"
            }
        }

        let result = Plaid.create(configuration)
        switch result {
        case .success(let handler):
            self.handler = handler
            guard let rootViewController = topViewController() else { return }
            handler.open(presentUsing: .viewController(rootViewController))
        case .failure(let error):
            errorMessage = "Couldn't create Plaid Link handler: \(error.localizedDescription)"
        }
    }

    private func openLink(linkToken: String) {
        var configuration = LinkTokenConfiguration(token: linkToken) { [weak self] success in
            self?.handleSuccess(success)
        }
        configuration.onExit = { [weak self] exit in
            if let error = exit.error {
                // String(describing:) compiles against any LinkKit version —
                // the error type's members have shifted across releases.
                self?.errorMessage = "Bank linking didn't finish: \(String(describing: error))"
            }
        }

        let result = Plaid.create(configuration)
        switch result {
        case .success(let handler):
            self.handler = handler
            guard let rootViewController = topViewController() else { return }
            handler.open(presentUsing: .viewController(rootViewController))
        case .failure(let error):
            errorMessage = "Couldn't create Plaid Link handler: \(error.localizedDescription)"
        }
    }

    private func handleSuccess(_ success: LinkSuccess) {
        guard let modelContext else {
            errorMessage = "Internal error: no data context for linking."
            return
        }
        Task {
            isFinishingLink = true
            defer { isFinishingLink = false }
            do {
                _ = try await PlaidAPIClient.exchangePublicToken(success.publicToken)

                // Plaid often needs a few seconds after the exchange before an
                // item's accounts are queryable, so poll briefly rather than
                // giving up on the first empty result.
                for attempt in 0..<5 {
                    if attempt > 0 {
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                    }
                    if await SyncEngine.shared.importNewAccounts(context: modelContext) > 0 {
                        didLinkAccounts = true
                        return
                    }
                }

                // Never fail silently: the bank IS linked server-side at this
                // point, so tell the user how to bring the accounts in.
                errorMessage = "Your bank is connected, but its accounts weren't ready yet — "
                    + "Plaid sometimes needs a minute. Pull down on the Dashboard to refresh "
                    + "and they'll appear."
            } catch {
                errorMessage = "Couldn't finish linking: \(error.localizedDescription)"
            }
        }
    }

    private func topViewController() -> UIViewController? {
        guard
            let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
            let root = scene.windows.first(where: \.isKeyWindow)?.rootViewController
        else { return nil }
        var top = root
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }
}

extension AccountType {
    /// Maps Plaid's `type`/`subtype` taxonomy onto our simplified AccountType.
    static func from(plaidType: String, subtype: String?) -> AccountType {
        switch (plaidType, subtype) {
        case ("depository", "checking"): return .checking
        case ("depository", "savings"): return .savings
        case ("credit", _): return .creditCard
        case ("loan", "student"): return .studentLoan
        case ("loan", "auto"): return .autoLoan
        case ("loan", "mortgage"): return .mortgage
        case ("loan", _): return .otherLoan
        case ("investment", "ira"): return .traditionalIRA
        case ("investment", "roth"), ("investment", "roth 401k"): return .rothIRA
        case ("investment", "401k"): return .fourOhOneK
        case ("investment", "hsa"): return .hsa
        default: return .otherAsset
        }
    }
}
