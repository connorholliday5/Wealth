import SwiftUI
import SwiftData

struct RootTabView: View {
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
        }
        .task {
            NotificationManager.shared.requestAuthorizationIfNeeded()
            NotificationManager.shared.rescheduleAll(bills: bills)
        }
    }
}

#Preview {
    RootTabView()
        .modelContainer(SampleData.container)
}
