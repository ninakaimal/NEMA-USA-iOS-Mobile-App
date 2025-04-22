//
//  NEMA_USAApp.swift
//  NEMA USA
//  Created by Sajith on 4/1/25.
//

import SwiftUI

@main
struct NEMA_USAApp: App {
    @UIApplicationDelegateAdaptor(PushNotificationDelegate.self)
    var appDelegate
    
    init() {
        configureNavigationBarAppearance()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

/// Globally styles your nav bars with your hex‑orange + white chevron/text
private func configureNavigationBarAppearance() {
    let navBar = UINavigationBar.appearance()
    navBar.tintColor = .white
    UIBarButtonItem.appearance().tintColor = .white     // ← **ADDED**: guard all bar‑buttons are white

    let orangeColor = UIColor(Color.orange) // from ColorHex.swift
    let whiteColor  = UIColor.white

    if #available(iOS 15.0, *) {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = orangeColor
        appearance.titleTextAttributes      = [.foregroundColor: whiteColor]
        appearance.largeTitleTextAttributes = [.foregroundColor: whiteColor]

        // Force the back‑chevron image to be white
        if let back = UIImage(systemName: "chevron.backward")?
                            .withTintColor(whiteColor, renderingMode: .alwaysOriginal) {
            appearance.setBackIndicatorImage(back, transitionMaskImage: back)
        }

        // Keep the "Back" text white
        let backText = UIBarButtonItemAppearance()
        backText.normal.titleTextAttributes = [.foregroundColor: whiteColor]
        appearance.backButtonAppearance = backText

        // ← **ADDED**: also apply to every other bar‑button style
        appearance.buttonAppearance     = backText
        appearance.doneButtonAppearance = backText

        navBar.standardAppearance   = appearance
        navBar.scrollEdgeAppearance = appearance
        navBar.compactAppearance    = appearance
    } else {
        // iOS 14 and below
        navBar.barTintColor             = orangeColor
        navBar.titleTextAttributes      = [.foregroundColor: whiteColor]
        navBar.largeTitleTextAttributes = [.foregroundColor: whiteColor]
    }
}
