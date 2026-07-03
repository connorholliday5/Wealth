import SwiftUI
import SwiftData

struct RootTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var bills: [Bill]

    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Dashboard", systemImage: "house") }

            AccountsListView()
                .tabItem { Label("Accounts", systemImage: "creditcard") }

            BillsListView()
                .tabItem { Label("Bills", systemImage: "calendar") }

            AdvisorView()
                .tabItem { Label("Advisor", systemImage: "sparkles") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gear") }
        }
        .task {
            // Order matters: roll overdue bills forward first, then schedule
            // reminders against the corrected due dates, then refresh linked
            // accounts (throttled to every 15 minutes).
            MaintenanceEngine.runLaunchMaintenance(context: modelContext)
            NotificationManager.shared.requestAuthorizationIfNeeded()
            NotificationManager.shared.rescheduleAll(bills: bills)
            await SyncEngine.shared.autoSyncIfStale(context: modelContext)
        }
    }
}

#Preview {
    RootTabView()
        .modelContainer(SampleData.container)
}
