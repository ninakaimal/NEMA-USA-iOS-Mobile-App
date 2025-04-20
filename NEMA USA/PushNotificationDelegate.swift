//
//  PushNotificationDelegate.swift
//  NEMA USA
//  Updated by ChatGPT on 4/18/25.
//

import UIKit
import UserNotifications
import OneSignalFramework

// 1) Deep‑link notification name
extension Notification.Name {
    /// Posted when a push contains an "eventId" and the user taps it.
    static let didDeepLinkToEvent = Notification.Name("didDeepLinkToEvent")
}

class PushNotificationDelegate: NSObject,
                                UIApplicationDelegate,
                                UNUserNotificationCenterDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // — Ask iOS for permission & register for APNs
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            print("iOS notification permission granted: \(granted), error: \(String(describing: error))")
        }
        application.registerForRemoteNotifications()

        // — Configure OneSignal
        let onesignalAppId = "9bbb3fd6-51d9-4eba-9644-1f34562cad65"
        OneSignal.Debug.setLogLevel(.LL_VERBOSE)
        OneSignal.Debug.setAlertLevel(.LL_NONE)
        OneSignal.initialize(onesignalAppId, withLaunchOptions: launchOptions)

        return true
    }

    // MARK: — UNUserNotificationCenterDelegate

    /// Show notifications even when app is foregrounded
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler:
            @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound, .badge])
    }

    /// Handle taps on notifications: extract "eventId" and broadcast
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        print("Tapped notification payload: \(userInfo)")

        if
            let additional = userInfo["additionalData"] as? [AnyHashable: Any],
            let eventId    = additional["eventId"] as? String
        {
            NotificationCenter.default.post(
                name: .didDeepLinkToEvent,
                object: nil,
                userInfo: ["eventId": eventId]
            )
        }

        completionHandler()
    }
}
