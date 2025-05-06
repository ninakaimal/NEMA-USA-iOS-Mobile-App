//
//  ContentView.swift
//  NEMA USA
//  Created by Nina on 4/1/25.
//

import SwiftUI

struct ContentView: View {
    // 1) Watch the token key so we know when login completes
    @AppStorage("laravelSessionToken") private var authToken: String?
    // 2) Track which tab is visible
    @State private var selectedTab = 0

    var body: some View {
        NavigationView {
            TabView(selection: $selectedTab) {
                DashboardView()
                    .tag(0)
                    .tabItem {
                        Image(systemName: "house")
                        Text("Dashboard")
                    }

                CalendarView()
                    .tag(1)
                    .tabItem {
                        Image(systemName: "calendar")
                        Text("Calendar")
                    }

                AccountView()
                    .tag(2)
                    .tabItem {
                        Image(systemName: "person.crop.circle")
                        Text("Account")
                    }

                ContactView()
                    .tag(3)
                    .tabItem {
                        Image(systemName: "message")
                        Text("Feedback")
                    }
            }
            .accentColor(.orange)

            // (your existing deep‑link NavigationLink background)
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}

