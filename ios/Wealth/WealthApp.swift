import SwiftUI
import SwiftData

@main
struct WealthApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([Account.self, Transaction.self, Bill.self, NetWorthSnapshot.self, Budget.self, SavingsGoal.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            // Container creation usually fails when an on-disk store no longer
            // matches the current schema (e.g. after a model change). Rather than
            // fatalError and brick the app on launch, move the incompatible store
            // aside and start fresh. The old data is NOT deleted — it's renamed to
            // a timestamped ".broken" backup on disk, so it stays recoverable.
            WealthApp.moveStoreAside()
            do {
                return try ModelContainer(for: schema, configurations: [configuration])
            } catch {
                fatalError("Could not create ModelContainer after resetting store: \(error)")
            }
        }
    }()

    /// Renames the default SwiftData store (and its -wal/-shm siblings) to a
    /// timestamped ".broken" backup so a fresh, empty store can be created in its
    /// place. Best-effort: failures are ignored (try?) since the retry will
    /// surface any real problem.
    private static func moveStoreAside() {
        let fileManager = FileManager.default
        let storeURL = URL.applicationSupportDirectory.appending(path: "default.store")
        let stamp = Int(Date().timeIntervalSince1970)
        for suffix in ["", "-wal", "-shm"] {
            let source = URL(fileURLWithPath: storeURL.path + suffix)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            let destination = URL(fileURLWithPath: storeURL.path + suffix + ".broken-\(stamp)")
            try? fileManager.moveItem(at: source, to: destination)
        }
    }

    var body: some Scene {
        WindowGroup {
            AppLockGate {
                RootTabView()
            }
        }
        .modelContainer(sharedModelContainer)
    }
}
