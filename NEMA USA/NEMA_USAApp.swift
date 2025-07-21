//
//  NEMA_USAApp.swift
//  NEMA USA
//  Created by Sajith on 4/1/25.
//  Updated by Sajith for local notifications on 7/21/25.


import Kingfisher
import SwiftUI

@main
struct NEMA_USAApp: App {
    @UIApplicationDelegateAdaptor(ServiceDelegate.self)
    var appDelegate

    @AppStorage("laravelSessionToken") private var authToken: String?
    @State private var passwordResetToken: PasswordResetToken?
    @State private var eventToDeepLink: String? = nil

    init() {
        configureNavigationBarAppearance()
        configureKingfisher()
    }
    
    func configureKingfisher() {
        // Create cache configuration
        let cache = ImageCache.default
        cache.memoryStorage.config.expiration = .seconds(300) // Memory cache expiration
        cache.diskStorage.config.expiration = .days(7) // Disk cache expiration
        cache.diskStorage.config.sizeLimit = 500 * 1024 * 1024 // 500 MB disk cache limit
        
        // Configure the default downloader
        let downloader = ImageDownloader.default
        downloader.downloadTimeout = 15.0 // 15 second timeout
        
        // Configure Kingfisher globally
        KingfisherManager.shared.defaultOptions = [
            .scaleFactor(UIScreen.main.scale),
            .transition(.fade(0.2)),
            .cacheOriginalImage,
            .backgroundDecode,
            .alsoPrefetchToMemory
        ]
        
        // Configure trusted hosts for test environment - disable in production
//        if let customDownloader = KingfisherManager.shared.downloader as? ImageDownloader {
//            customDownloader.trustedHosts = ["nemausa.org"]
//        }
        print("✅ Kingfisher configured with optimized caching settings")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    authToken = nil
                    // Request notification permissions on app start
                    Task {
                        await requestNotificationPermissions()
                    }
                }
                .onOpenURL { url in
                    handleUniversalLink(url: url)
                }
                .sheet(item: $passwordResetToken) { token in
                    PasswordResetView(mode: .reset(token: token.id))
                }
                .onReceive(NotificationCenter.default.publisher(for: .didSessionExpire)) { _ in
                    DispatchQueue.main.async {
                        print("🔒 [App] Session expired globally - clearing all session data")
                        DatabaseManager.shared.clearSession()
                        // The individual views (MyEventsView) will handle showing login
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .didDeepLinkToEvent)) { notification in
                    if let userInfo = notification.userInfo,
                       let eventId = userInfo["eventId"] as? String,
                       let source = userInfo["source"] as? String {
                        print("🔗 [App] Deep link received for event \(eventId) from \(source)")
                        DispatchQueue.main.async {
                            eventToDeepLink = eventId
                        }
                    }
                }
                .sheet(item: Binding<EventDeepLink?>(
                    get: { eventToDeepLink.map { EventDeepLink(eventId: $0) } },
                    set: { _ in eventToDeepLink = nil }
                )) { deepLink in
                    // Navigate to EventDetailView when deep link is triggered
                    EventDeepLinkView(eventId: deepLink.eventId)
                }
        }
    }
    
    private func requestNotificationPermissions() async {
        var prefs = DatabaseManager.shared.notificationPreferences
        
        // Only request if we haven't asked before
        guard !prefs.hasRequestedPermission else {
            print("📱 [App] Notification permission already requested")
            return
        }
        
        let granted = await NotificationManager.shared.requestNotificationPermission()
        prefs.hasRequestedPermission = true
        prefs.isEnabled = granted
        DatabaseManager.shared.notificationPreferences = prefs
        print("📱 [App] Notification permission granted: \(granted)")
    }

    private func handleUniversalLink(url: URL) {
        guard url.host == "nemausa.org",
              url.path.starts(with: "/user/reset_password"),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let token = components.queryItems?.first(where: { $0.name == "token" })?.value else {
            return
        }

        passwordResetToken = PasswordResetToken(id: token)
    }
}

// MARK: - Supporting Types

// Clearly defined within the same file
struct PasswordResetToken: Identifiable {
    let id: String
}

struct EventDeepLink: Identifiable {
    let id = UUID()
    let eventId: String
}

struct EventDeepLinkView: View {
    let eventId: String
    @StateObject private var eventRepository = EventRepository()
    @Environment(\.presentationMode) private var presentationMode
    
    var body: some View {
        NavigationView {
            Group {
                if let event = eventRepository.events.first(where: { $0.id == eventId }) {
                    EventDetailView(event: event)
                } else if eventRepository.isLoading {
                    VStack {
                        ProgressView()
                        Text("Loading event details...")
                            .padding(.top)
                    }
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "calendar.badge.exclamationmark")
                            .font(.system(size: 50))
                            .foregroundColor(.orange)
                        Text("Event Not Found")
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text("The event you're looking for might have been removed or is no longer available.")
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                        Button("Close") {
                            presentationMode.wrappedValue.dismiss()
                        }
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.orange)
                        .cornerRadius(10)
                        .padding(.horizontal)
                    }
                    .padding()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        presentationMode.wrappedValue.dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
        }
        .task {
            if eventRepository.events.isEmpty {
                await eventRepository.loadEventsFromCoreData()
                await eventRepository.syncAllEvents()
            }
        }
    }
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
} // end of file
