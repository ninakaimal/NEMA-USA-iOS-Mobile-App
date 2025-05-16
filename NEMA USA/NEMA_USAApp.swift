//
//  NEMA_USAApp.swift
//  NEMA USA
//  Created by Sajith on 4/1/25.
//

import SwiftUI

@main
struct NEMA_USAApp: App {
    @UIApplicationDelegateAdaptor(ServiceDelegate.self)
    var appDelegate

    @AppStorage("laravelSessionToken") private var authToken: String?
    @State private var passwordResetToken: PasswordResetToken?

    init() {
        configureNavigationBarAppearance()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                // ← force a fresh login on every cold start
                .onAppear {
                authToken = nil
                }
                .onOpenURL { url in
                    handleUniversalLink(url: url)
                }
                .sheet(item: $passwordResetToken) { token in
                    PasswordResetView(mode: .reset(token: token.id))
                }
        }
    }

    private func handleUniversalLink(url: URL) {
        guard url.host == "test.nemausa.org",
              url.path.starts(with: "/user/reset_password"),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let token = components.queryItems?.first(where: { $0.name == "token" })?.value else {
            return
        }

        passwordResetToken = PasswordResetToken(id: token)
    }
}

// Clearly defined within the same file
struct PasswordResetToken: Identifiable {
    let id: String
}

private func configureNavigationBarAppearance() {
    let navBar = UINavigationBar.appearance()
    navBar.tintColor = .white
    UIBarButtonItem.appearance().tintColor = .white

    let orangeColor = UIColor(Color.orange)
    let whiteColor  = UIColor.white

    if #available(iOS 15.0, *) {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = orangeColor
        appearance.titleTextAttributes      = [.foregroundColor: whiteColor]
        appearance.largeTitleTextAttributes = [.foregroundColor: whiteColor]

        if let back = UIImage(systemName: "chevron.backward")?
                            .withTintColor(whiteColor, renderingMode: .alwaysOriginal) {
            appearance.setBackIndicatorImage(back, transitionMaskImage: back)
        }

        let backText = UIBarButtonItemAppearance()
        backText.normal.titleTextAttributes = [.foregroundColor: whiteColor]
        appearance.backButtonAppearance = backText
        appearance.buttonAppearance     = backText
        appearance.doneButtonAppearance = backText

        navBar.standardAppearance   = appearance
        navBar.scrollEdgeAppearance = appearance
        navBar.compactAppearance    = appearance
    } else {
        navBar.barTintColor             = orangeColor
        navBar.titleTextAttributes      = [.foregroundColor: whiteColor]
        navBar.largeTitleTextAttributes = [.foregroundColor: whiteColor]
    }
}
