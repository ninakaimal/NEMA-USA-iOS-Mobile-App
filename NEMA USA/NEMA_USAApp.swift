//
//  NEMA_USAApp.swift
//  NEMA USA
//  Created by Sajith on 4/1/25.
//  Updated by Sajith for local notifications on 7/21/25.
//  Updated by Sajith to add force upgrade on 7/28/25.


import Kingfisher
import SwiftUI

@main
struct NEMA_USAApp: App {
    @UIApplicationDelegateAdaptor(ServiceDelegate.self)
    var appDelegate

    @AppStorage("laravelSessionToken") private var authToken: String?
    @State private var passwordResetToken: PasswordResetToken?
    @State private var showBiometricSetupPrompt = false
    @State private var eventToDeepLink: String? = nil

    
    // Version checking state
    @StateObject private var versionManager = AppVersionManager.shared
    @State private var showUpdatePrompt = false
    @State private var showUpdateError = false

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
                        // Check for app updates after app setup
                        await checkForUpdatesOnLaunch()
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
                // Version checking UI
                .onChange(of: versionManager.updateType) { updateType in
                    switch updateType {
                    case .none:
                        showUpdatePrompt = false
                    case .optional, .mandatory:
                        showUpdatePrompt = true
                    }
                }
                .onChange(of: versionManager.lastError != nil) { hasError in
                    showUpdateError = hasError
                }
                .sheet(isPresented: $showUpdatePrompt) {
                    UpdatePromptView(updateType: versionManager.updateType, versionManager: versionManager)
                }
                .sheet(isPresented: $showUpdateError) {
                    if let error = versionManager.lastError {
                        UpdateErrorView(
                            error: error,
                            onRetry: {
                                showUpdateError = false
                                Task {
                                    await versionManager.checkForUpdates(forced: true)
                                }
                            },
                            onDismiss: {
                                showUpdateError = false
                            }
                        )
                    }
                }
            // FaceID setup alert
            .alert("Enable Face ID Login?", isPresented: $showBiometricSetupPrompt) {
                Button("Enable") {
                    enableBiometricFromApp()
                }
                Button("Not Now", role: .cancel) {
                    DatabaseManager.shared.disableBiometricAuth()
                }
            } message: {
                Text("Use Face ID to quickly and securely log into your NEMA account.")
            }

            // Listen for successful JWT login
            .onReceive(NotificationCenter.default.publisher(for: .didReceiveJWT)) { _ in
                // Check for biometric setup after successful login
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                    checkForBiometricSetup()
                }
            }
        }
    }
            
    // Version checking method
    private func checkForUpdatesOnLaunch() async {
        print("📱 [App] Starting version check...")
        print("📱 [App] Bundle ID: \(Bundle.main.bundleIdentifier ?? "unknown")")
        print("📱 [App] Current version: \(versionManager.getCurrentAppVersion())")
        
//        // ========= ADD TEST CODE HERE (Line 177) =========
//        #if DEBUG
//        // Wait 2 seconds then force show update popup for testing
//        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
//            print("🧪 [TEST] Forcing update popup for testing")
//
//            let testVersionInfo = AppStoreVersionInfo(
//                version: "1.0.12",  // Fake newer version
//                trackId: 6738434547,  // Your app ID
//                trackViewUrl: "itms-apps://apps.apple.com/us/app/nema-usa/id6744124012",
//                releaseNotes: "• Bug fixes and improvements\n• Performance enhancements\n• New features added",
//                currentVersionReleaseDate: "2025-08-14"
//            )
//
//           // Force the update popup to show
//            self.versionManager.updateType = .optional(testVersionInfo)
//            self.showUpdatePrompt = true  // Force the sheet to show
//
//            print("🧪 [TEST] Update popup should now be visible")
//        }
//        return  // Skip real check during testing
//        #endif
//        // ========= END TEST CODE =========
        
        await versionManager.checkForUpdates()
        
        // Add debugging after check completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            print("📱 [App] Version check complete:")
            print("  - Update type: \(self.versionManager.updateType)")
            print("  - Available version: \(self.versionManager.availableVersion ?? "none")")
            print("  - Has update: \(self.versionManager.hasUpdate)")
            print("  - Show prompt state: \(self.showUpdatePrompt)")
            
            if let error = self.versionManager.lastError {
                print("  - Error: \(error)")
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
    
    private func checkForBiometricSetup() {
        let canUseBiometric = BiometricAuthManager.shared.isBiometricAvailable() &&
                             BiometricAuthManager.shared.isBiometricEnrolled()
        
        print("🔍 [App] checkForBiometricSetup - canUseBiometric: \(canUseBiometric), shouldAsk: \(DatabaseManager.shared.shouldAskForBiometricSetup())")
        
        if canUseBiometric && DatabaseManager.shared.shouldAskForBiometricSetup() {
            print("🔍 [App] Showing biometric setup prompt on main app")
            showBiometricSetupPrompt = true
        }
    }

    private func enableBiometricFromApp() {
        // Check if credentials are available from the recent login
        if KeychainManager.shared.hasCredentials() {
            DatabaseManager.shared.enableBiometricAuth()
            print("✅ [App] FaceID enabled from main app")
            
            // ADD THIS LINE: Post notification to update LoginView UI
            NotificationCenter.default.post(name: .didUpdateBiometricSettings, object: nil)
            
            // Test biometric authentication immediately
            testBiometricAuthentication()
        } else {
            // Credentials not available, disable biometric
            DatabaseManager.shared.disableBiometricAuth()
            print("⚠️ [App] No credentials available for FaceID")
            
            // ADD THIS LINE: Post notification even for disable
            NotificationCenter.default.post(name: .didUpdateBiometricSettings, object: nil)
        }
    }
    
    // MARK: - NEW METHOD: Test biometric immediately after enabling
    private func testBiometricAuthentication() {
        print("🔍 [App] Testing biometric authentication immediately")
        
        Task {
            let result = await BiometricAuthManager.shared.authenticate(
                reason: "Verify Face ID is working correctly"
            )
            
            await MainActor.run {
                switch result {
                case .success:
                    print("✅ [App] Biometric test successful - Face ID is working!")
                    // Biometric is working, keep it enabled
                case .failure(let error):
                    print("❌ [App] Biometric test failed: \(error)")
                    // If the test fails, optionally disable biometric
                    // DatabaseManager.shared.disableBiometricAuth()
                }
            }
        }
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
