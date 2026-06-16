import SwiftUI

struct RootTabView: View {
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
    }
}

#Preview {
    RootTabView()
        .modelContainer(SampleData.container)
}
