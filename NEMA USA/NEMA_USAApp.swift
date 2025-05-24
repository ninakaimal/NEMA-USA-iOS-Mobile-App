//
//  NEMA_USAApp.swift
//  NEMA USA
//  Created by Sajith on 4/1/25.
//
import Kingfisher
import SwiftUI

@main
struct NEMA_USAApp: App {
    @UIApplicationDelegateAdaptor(ServiceDelegate.self)
    var appDelegate

    @AppStorage("laravelSessionToken") private var authToken: String?
    @State private var passwordResetToken: PasswordResetToken?

    init() {
        configureNavigationBarAppearance()
        configureKingfisherForTest()
    }
    
    func configureKingfisherForTest() {
        // You no longer need to create an instance of InsecureTrustDelegate for this.
        // let sessionDelegate = InsecureTrustDelegate()
        
        // You also don't need to create a separate URLSessionConfiguration for this specific purpose,
        // as Kingfisher's ImageDownloader will manage its own.
        // let configuration = URLSessionConfiguration.default

        // 1. Create your ImageDownloader instance.
        let downloader = ImageDownloader(name: "customInsecureDownloader")

        // 2. Configure the trustedHosts property. ✅
        downloader.trustedHosts = ["test.nemausa.org"]

        // 3. Set this downloader as the default for Kingfisher.
        KingfisherManager.shared.downloader = downloader
        
        print("⚠️ Kingfisher configured with 'test.nemausa.org' in trustedHosts (DEVELOPMENT ONLY).")
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
