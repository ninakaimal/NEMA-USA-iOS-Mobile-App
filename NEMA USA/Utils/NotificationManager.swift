//
//  NotificationManager.swift
//  NEMA USA
//
//  Created by Nina Kaimal on 7/21/25.
//
import Foundation
import UserNotifications

class NotificationManager: NSObject {
    static let shared = NotificationManager()
    
    private override init() {
        super.init()
    }
    
    // MARK: - Permission Management
    
    func requestNotificationPermission() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .sound, .badge]
            )
            print("📱 [NotificationManager] Local notification permission: \(granted)")
            return granted
        } catch {
            print("❌ [NotificationManager] Permission request failed: \(error)")
            return false
        }
    }
    
    func checkNotificationPermissions() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus == .authorized
    }
    
    // MARK: - User Preferences
    
    private let notificationsEnabledKey = "localNotificationsEnabled"
    private let notification24hEnabledKey = "notification24hEnabled"
    private let notification90minEnabledKey = "notification90minEnabled"
    
    var areNotificationsEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: notificationsEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: notificationsEnabledKey) }
    }
    
    var is24HourNotificationEnabled: Bool {
        get { UserDefaults.standard.object(forKey: notification24hEnabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: notification24hEnabledKey) }
    }
    
    var is90MinNotificationEnabled: Bool {
        get { UserDefaults.standard.object(forKey: notification90minEnabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: notification90minEnabledKey) }
    }
    
    // MARK: - Notification Scheduling
    
    func scheduleEventNotifications(for events: [Event]) async {
        // Only proceed if user has enabled notifications and granted permission
        guard areNotificationsEnabled, await checkNotificationPermissions() else {
            print("🔕 [NotificationManager] Notifications disabled or no permission")
            return
        }
        
        let now = Date()
        let calendar = Calendar.current
        
        for event in events {
            guard let eventDate = event.date,
                  eventDate > now else {
                print("⏭️ [NotificationManager] Skipping past event: \(event.title)")
                continue
            }
            
            // Schedule 24-hour notification
            if is24HourNotificationEnabled {
                if let notification24h = calendar.date(byAdding: .hour, value: -24, to: eventDate),
                   notification24h > now {
                    await scheduleNotification(
                        eventId: event.id,
                        title: "Event Tomorrow",
                        body: "\(event.title) is happening tomorrow at \(event.timeString ?? "TBA")",
                        triggerDate: notification24h,
                        timeType: "24h"
                    )
                }
            }
            
            // Schedule 1.5-hour notification
            if is90MinNotificationEnabled {
                if let notification90min = calendar.date(byAdding: .minute, value: -90, to: eventDate),
                   notification90min > now {
                    await scheduleNotification(
                        eventId: event.id,
                        title: "Event Starting Soon",
                        body: "\(event.title) starts in 1.5 hours. Don't forget!",
                        triggerDate: notification90min,
                        timeType: "90min"
                    )
                }
            }
        }
        
        await logScheduledNotifications()
    }
    
    private func scheduleNotification(
        eventId: String,
        title: String,
        body: String,
        triggerDate: Date,
        timeType: String
    ) async {
        let identifier = "event_\(eventId)_\(timeType)"
        
        // Create notification content
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = [
            "eventId": eventId,
            "type": "localEventReminder",
            "timeType": timeType
        ]
        
        // Create trigger
        let triggerComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: triggerDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComponents, repeats: false)
        
        // Create request
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        
        do {
            try await UNUserNotificationCenter.current().add(request)
            print("✅ [NotificationManager] Scheduled \(timeType) notification for event \(eventId) at \(triggerDate)")
        } catch {
            print("❌ [NotificationManager] Failed to schedule notification: \(error)")
        }
    }
    
    // MARK: - Notification Management
    
    func cancelAllEventNotifications() async {
        let center = UNUserNotificationCenter.current()
        let pendingRequests = await center.pendingNotificationRequests()
        let eventNotificationIds = pendingRequests
            .filter { $0.identifier.hasPrefix("event_") }
            .map { $0.identifier }
        
        center.removePendingNotificationRequests(withIdentifiers: eventNotificationIds)
        print("🗑️ [NotificationManager] Cancelled \(eventNotificationIds.count) event notifications")
    }
    
    func cancelNotifications(for eventId: String) async {
        let identifiersToCancel = [
            "event_\(eventId)_24h",
            "event_\(eventId)_90min"
        ]
        
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiersToCancel)
        print("🗑️ [NotificationManager] Cancelled notifications for event \(eventId)")
    }
    
    // MARK: - Debug Helpers
    
    private func logScheduledNotifications() async {
        let center = UNUserNotificationCenter.current()
        let pendingRequests = await center.pendingNotificationRequests()
        let eventNotifications = pendingRequests.filter { $0.identifier.hasPrefix("event_") }
        
        print("📋 [NotificationManager] Currently scheduled event notifications: \(eventNotifications.count)")
        for request in eventNotifications.prefix(5) {
            if let trigger = request.trigger as? UNCalendarNotificationTrigger,
               let nextDate = trigger.nextTriggerDate() {
                print("   • \(request.identifier): \(nextDate)")
            }
        }
    }
    
    func getScheduledNotificationsCount() async -> Int {
        let center = UNUserNotificationCenter.current()
        let pendingRequests = await center.pendingNotificationRequests()
        return pendingRequests.filter { $0.identifier.hasPrefix("event_") }.count
    }
}

