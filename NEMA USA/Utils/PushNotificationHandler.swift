//
//  PushNotificationHandler.swift
//  NEMA USA
//
//  Created by Sajith on 5/8/25.
//

import Foundation
import UIKit
import UserNotifications

class PushNotificationHandler {

    func registerPushNotifications(_ application: UIApplication) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if let error = error {
                print("Push Notification Authorization failed: \(error)")
                return
            }
            guard granted else {
                print("User denied push notification authorization.")
                return
            }
            DispatchQueue.main.async {
                application.registerForRemoteNotifications()
            }
        }
    }

    func didRegister(deviceToken: Data) {
        let tokenParts = deviceToken.map { String(format: "%02.2hhx", $0) }
        let token = tokenParts.joined()
        print("Device Token: \(token)")
        // Backend registration logic (if needed)
    }

    func didFailToRegister(error: Error) {
        print("Failed to register for remote notifications: \(error)")
    }
}
