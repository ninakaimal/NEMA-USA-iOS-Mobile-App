//
// ServiceDelegate.swift
// NEMA USA
//
// Created by Sajith on 4/18/25.
// Updated by Sajith on 7/21/25 - Handle Local Notifications

import UIKit
import UserNotifications
import OneSignalFramework

class ServiceDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    
//    private let paypalHandler = PayPalCallbackHandler()
    
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        
        // Configure local notifications
        configureLocalNotifications()
        
        // OneSignal Initialization
        configureOneSignal(with: launchOptions)
        
        return true
    }
    
    // ADD: Background app refresh for version checking
    func applicationDidBecomeActive(_ application: UIApplication) {
        print("📱 [ServiceDelegate] App became active - checking for updates")
        Task {
            // Force check when app becomes active to ensure "Remind Later" works
            await AppVersionManager.shared.checkForUpdates(forced: true)
        }
    }
    
    // ADD: Handle background app refresh
    func application(_ application: UIApplication, performFetchWithCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        print("📱 [ServiceDelegate] Background fetch - checking for updates")
        Task {
            await AppVersionManager.shared.checkForUpdates()
            completionHandler(.newData)
        }
    }
    
    private func configureLocalNotifications() {
        UNUserNotificationCenter.current().delegate = self
        print("📱 [ServiceDelegate] Local notification center delegate set")
    }
    
    private func configureOneSignal(with launchOptions: [UIApplication.LaunchOptionsKey: Any]?) {
        
        let onesignalAppId = "9bbb3fd6-51d9-4eba-9644-1f34562cad65"
        OneSignal.initialize(onesignalAppId, withLaunchOptions: launchOptions)
        
        OneSignal.Notifications.requestPermission { accepted in
            print("OneSignal permission accepted: \(accepted)")
        }
    }
    
    // MARK: - UNUserNotificationCenterDelegate
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler:
        @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound, .badge])
    }
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        
        // Handle local event reminder notifications
        if let type = userInfo["type"] as? String, type == "localEventReminder",
           let eventId = userInfo["eventId"] as? String {
            print("📱 [ServiceDelegate] Local event notification tapped for event: \(eventId)")
            NotificationCenter.default.post(
                name: .didDeepLinkToEvent,
                object: nil,
                userInfo: ["eventId": eventId, "source": "localNotification"]
            )
        }
        
        else if let additional = userInfo["additionalData"] as? [AnyHashable: Any],
           let eventId = additional["eventId"] as? String {
            print("📱 [ServiceDelegate] OneSignal notification tapped for event: \(eventId)")
            NotificationCenter.default.post(
                name: .didDeepLinkToEvent,
                object: nil,
                userInfo: ["eventId": eventId, "source": "oneSignal"]
            )
        }
        completionHandler()
    }
    // Remove paypal handler but keeping for traceablity
    //    func application(_ application: UIApplication,
    //                     open url: URL,
    //                     options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
    //        if paypalHandler.canHandle(url: url) {
    //            paypalHandler.handle(url: url)
    //            return true
    //        }
    //        return false
    //    }
    
}

extension Notification.Name {
    static let didDeepLinkToEvent = Notification.Name("didDeepLinkToEvent")
}
