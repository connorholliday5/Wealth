import SwiftUI
import SwiftData

@main
struct WealthApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([Account.self, Transaction.self, Bill.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            AppLockGate {
                RootTabView()
            }
        }
        .modelContainer(sharedModelContainer)
    }
}
