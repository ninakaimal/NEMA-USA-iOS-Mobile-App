//
//  NEMA_USAApp.swift
//  NEMA USA
//
//  Created by Sajith on 4/1/25.
//

import SwiftUI

@main
struct NEMA_USAApp: App {
    @UIApplicationDelegateAdaptor(PushNotificationDelegate.self) var appDelegate
    var body: some Scene {
        WindowGroup {
            ContentView()
            // LoginView()
            // DashboardView()
        }
    }
}
