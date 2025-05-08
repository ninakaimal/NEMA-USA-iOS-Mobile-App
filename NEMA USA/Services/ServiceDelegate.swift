//
//  ServiceDelegate.swift
//  NEMA USA
//
//  Created by Sajith on 4/18/25.
//

import UIKit
import UserNotifications
import OneSignalFramework

class ServiceDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    private let paypalHandler = PayPalCallbackHandler()

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {

        // Register PayPal Observer
        paypalHandler.registerCallbackObserver()

        // OneSignal Initialization
        configureOneSignal(with: launchOptions)

        return true
    }

    private func configureOneSignal(with launchOptions: [UIApplication.LaunchOptionsKey: Any]?) {
        UNUserNotificationCenter.current().delegate = self

        let onesignalAppId = "9bbb3fd6-51d9-4eba-9644-1f34562cad65"
        OneSignal.initialize(onesignalAppId, withLaunchOptions: launchOptions)

        OneSignal.Notifications.requestPermission { accepted in
            print("OneSignal permission accepted: \(accepted)")
        }
    }

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
        if let additional = userInfo["additionalData"] as? [AnyHashable: Any],
           let eventId = additional["eventId"] as? String {
            NotificationCenter.default.post(
                name: .didDeepLinkToEvent,
                object: nil,
                userInfo: ["eventId": eventId]
            )
        }
        completionHandler()
    }

    func application(_ application: UIApplication,
                     open url: URL,
                     options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        if paypalHandler.canHandle(url: url) {
            paypalHandler.handle(url: url)
            return true
        }
        return false
    }
}

extension Notification.Name {
    static let didDeepLinkToEvent = Notification.Name("didDeepLinkToEvent")
}
