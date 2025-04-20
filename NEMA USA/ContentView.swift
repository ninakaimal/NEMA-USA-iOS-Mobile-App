//
//  ContentView.swift
//  NEMA USA
//  Created by Nina on 4/1/25.
//


import SwiftUI

struct ContentView: View {
    // 1) Load all events so we can lookup by ID
    @StateObject private var loader = EventLoader()
    
    // 2) Hold the deep‑linked event and toggle for NavigationLink
    @State private var deepLinkEvent: Event?
    @State private var showDeepLink = false

    var body: some View {
        NavigationView {
            TabView {
                DashboardView()
                    .tabItem {
                        Image(systemName: "house")
                        Text("Dashboard")
                    }

                CalendarView()
                    .tabItem {
                        Image(systemName: "calendar")
                        Text("Calendar")
                    }

                ContactView()
                    .tabItem {
                        Image(systemName: "message")
                        Text("Feedback")
                    }
            }
            .accentColor(Color.orange)

            // 3) Invisible link that triggers when `showDeepLink` flips true
            .background(
                NavigationLink(
                    destination: Group {
                        if let ev = deepLinkEvent {
                            EventDetailView(event: ev)
                        } else {
                            EmptyView()
                        }
                    },
                    isActive: $showDeepLink
                ) {
                    EmptyView()
                }
                .hidden()
            )
            // 4) Listen for the notification and lookup the Event by ID
               .onReceive(NotificationCenter.default.publisher(for: .didDeepLinkToEvent)) { notif in
                   guard
                     let info     = notif.userInfo,
                     let eventId  = info["eventId"] as? String,
                     let ev       = loader.events.first(where: { $0.id == eventId })
                   else {
                     return
                   }
                deepLinkEvent = ev
                showDeepLink  = true
            }
        }
        // Force stack style so TabView + NavigationLink works predictably on iOS
        .navigationViewStyle(StackNavigationViewStyle())
    }
}
