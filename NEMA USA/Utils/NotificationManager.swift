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
    
    // MARK: - State Tracking for Delta Changes
    
    private let lastScheduledEventsKey = "lastScheduledEvents"
    private let lastNotificationSettingsKey = "lastNotificationSettings"
    
    private struct EventFingerprint: Codable, Hashable {
        let id: String
        let title: String
        let date: Date?
        let timeString: String?
        let lastUpdatedAt: Date?
        
        static func from(_ event: Event) -> EventFingerprint {
            return EventFingerprint(
                id: event.id,
                title: event.title,
                date: event.date,
                timeString: event.timeString,
                lastUpdatedAt: event.lastUpdatedAt
            )
        }
    }
    
    private struct NotificationSettings: Codable, Hashable {
        let isEnabled: Bool
        let enable24Hours: Bool
        let enable90Minutes: Bool
        
        static var current: NotificationSettings {
            let manager = NotificationManager.shared
            return NotificationSettings(
                isEnabled: manager.areNotificationsEnabled,
                enable24Hours: manager.is24HourNotificationEnabled,
                enable90Minutes: manager.is90MinNotificationEnabled
            )
        }
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
    
    // MARK: - Smart Delta-Based Notification Scheduling
    
    func scheduleEventNotifications(for events: [Event]) async {
        // Corner Case 1: Check permissions first
        guard await checkNotificationPermissions() else {
            print("🔕 [NotificationManager] No notification permission - clearing any existing notifications")
            await cancelAllEventNotifications()
            return
        }
        
        // Corner Case 2: Notifications disabled
        guard areNotificationsEnabled else {
            print("🔕 [NotificationManager] Notifications disabled - clearing existing notifications")
            await cancelAllEventNotifications()
            clearStoredState()
            return
        }
        
        // Corner Case 3: No timing preferences selected
        guard is24HourNotificationEnabled || is90MinNotificationEnabled else {
            print("🔕 [NotificationManager] No notification timings enabled - clearing existing notifications")
            await cancelAllEventNotifications()
            clearStoredState()
            return
        }
        
        let currentFingerprints = Set(events.map(EventFingerprint.from))
        let currentSettings = NotificationSettings.current
        
        // Check if we need to reschedule (delta detection)
        let needsReschedule = await shouldRescheduleNotifications(
            currentFingerprints: currentFingerprints,
            currentSettings: currentSettings
        )
        
        if !needsReschedule {
            print("✅ [NotificationManager] No changes detected - keeping existing notifications")
            return
        }
        
        print("🔄 [NotificationManager] Delta changes detected - rescheduling notifications...")
        
        // Clean slate approach for reliability
        await cancelAllEventNotifications()
        
        // Schedule fresh notifications
        let scheduledCount = await scheduleNotificationsForValidEvents(events)
        
        // Store current state for future delta comparison
        storeCurrentState(fingerprints: currentFingerprints, settings: currentSettings)
        
        print("✅ [NotificationManager] Scheduled \(scheduledCount) notifications for \(events.count) events")
        await logScheduledNotifications()
    }
    
    private func shouldRescheduleNotifications(
        currentFingerprints: Set<EventFingerprint>,
        currentSettings: NotificationSettings
    ) async -> Bool {
        
        // Check if settings changed
        let lastSettings = getStoredSettings()
        if lastSettings != currentSettings {
            print("⚙️ [NotificationManager] Settings changed - reschedule needed")
            return true
        }
        
        // Check if events changed
        let lastFingerprints = getStoredFingerprints()
        if lastFingerprints != currentFingerprints {
            print("📅 [NotificationManager] Event data changed - reschedule needed")
            if lastFingerprints.count != currentFingerprints.count {
                print("   Event count: \(lastFingerprints.count) → \(currentFingerprints.count)")
            }
            return true
        }
        
        // Corner Case 4: Check if any existing notifications became invalid (past date)
        let hasInvalidNotifications = await checkForInvalidNotifications()
        if hasInvalidNotifications {
            print("⏰ [NotificationManager] Found invalid/past notifications - cleanup needed")
            return true
        }
        
        // Corner Case 5: Verify notification count matches expectations
        let expectedCount = await calculateExpectedNotificationCount(for: Array(currentFingerprints))
        let actualCount = await getScheduledNotificationsCount()
        if expectedCount != actualCount {
            print("🔍 [NotificationManager] Notification count mismatch (expected: \(expectedCount), actual: \(actualCount)) - reschedule needed")
            return true
        }
        
        return false
    }
    
    private func scheduleNotificationsForValidEvents(_ events: [Event]) async -> Int {
        let now = Date()
        let calendar = Calendar.current
        var scheduledCount = 0
        
        for event in events {
            // Corner Case 6: Handle events with nil dates
            guard let eventDate = event.date else {
                print("⚠️ [NotificationManager] Skipping event '\(event.title)' - no date")
                continue
            }
            
            // Corner Case 7: Handle past events
            guard eventDate > now else {
                print("⏭️ [NotificationManager] Skipping past event '\(event.title)' (was: \(eventDate.formatted()))")
                continue
            }
            
            // Corner Case 8: Handle events too far in future (iOS limitation)
            let maxFutureDate = calendar.date(byAdding: .day, value: 64, to: now) // iOS ~64 notifications limit
            guard eventDate <= maxFutureDate ?? .distantFuture else {
                print("⏭️ [NotificationManager] Skipping far-future event '\(event.title)' (date: \(eventDate.formatted()))")
                continue
            }
            
            // Corner Case 9: Handle malformed event titles
            let safeTitle = event.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !safeTitle.isEmpty else {
                print("⚠️ [NotificationManager] Skipping event with empty title (ID: \(event.id))")
                continue
            }
            
            // Schedule 24-hour notification
            if is24HourNotificationEnabled {
                if let notification24h = calendar.date(byAdding: .hour, value: -24, to: eventDate),
                   notification24h > now {
                    let success = await scheduleNotification(
                        eventId: event.id,
                        eventTitle: safeTitle,
                        eventTime: event.timeString ?? "Time TBA",
                        eventDate: eventDate,
                        title: "Event Tomorrow",
                        body: "\(safeTitle) is happening tomorrow at \(event.timeString ?? "TBA")",
                        triggerDate: notification24h,
                        timeType: "24h"
                    )
                    if success { scheduledCount += 1 }
                } else {
                    print("⏰ [NotificationManager] 24h reminder for '\(safeTitle)' would be in the past - skipping")
                }
            }
            
            // Schedule 1.5-hour notification
            if is90MinNotificationEnabled {
                if let notification90min = calendar.date(byAdding: .minute, value: -90, to: eventDate),
                   notification90min > now {
                    let success = await scheduleNotification(
                        eventId: event.id,
                        eventTitle: safeTitle,
                        eventTime: event.timeString ?? "Time TBA",
                        eventDate: eventDate,
                        title: "Event Starting Soon",
                        body: "\(safeTitle) starts in 1.5 hours. Don't forget!",
                        triggerDate: notification90min,
                        timeType: "90min"
                    )
                    if success { scheduledCount += 1 }
                } else {
                    print("⏰ [NotificationManager] 90min reminder for '\(safeTitle)' would be in the past - skipping")
                }
            }
        }
        
        return scheduledCount
    }
    
    private func scheduleNotification(
        eventId: String,
        eventTitle: String,
        eventTime: String,
        eventDate: Date,
        title: String,
        body: String,
        triggerDate: Date,
        timeType: String
    ) async -> Bool {
        
        // Corner Case 10: Validate notification content
        guard !eventId.isEmpty,
              !eventTitle.isEmpty,
              !title.isEmpty,
              !body.isEmpty else {
            print("❌ [NotificationManager] Invalid notification content for event \(eventId)")
            return false
        }
        
        let identifier = "event_\(eventId)_\(timeType)"
        
        // Corner Case 11: Validate identifier uniqueness
        let existingRequest = await UNUserNotificationCenter.current().pendingNotificationRequests()
            .first { $0.identifier == identifier }
        if existingRequest != nil {
            print("⚠️ [NotificationManager] Notification \(identifier) already exists - removing first")
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
        }
        
        // Create notification content with comprehensive metadata
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = [
            "eventId": eventId,
            "type": "localEventReminder",
            "timeType": timeType,
            "eventTitle": eventTitle,
            "eventTime": eventTime,
            "eventDate": ISO8601DateFormatter().string(from: eventDate),
            "scheduledFor": ISO8601DateFormatter().string(from: triggerDate),
            "createdAt": ISO8601DateFormatter().string(from: Date()),
            "version": "1.0"
        ]
        
        // Corner Case 12: Handle edge case date components
        let triggerComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: triggerDate)
        
        // Validate date components
        guard let year = triggerComponents.year,
              let month = triggerComponents.month,
              let day = triggerComponents.day,
              let hour = triggerComponents.hour,
              let minute = triggerComponents.minute,
              year > 2024 && year < 2030,
              month >= 1 && month <= 12,
              day >= 1 && day <= 31,
              hour >= 0 && hour <= 23,
              minute >= 0 && minute <= 59 else {
            print("❌ [NotificationManager] Invalid date components for \(identifier): \(triggerComponents)")
            return false
        }
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComponents, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        
        do {
            try await UNUserNotificationCenter.current().add(request)
            print("✅ [NotificationManager] Scheduled \(timeType) for '\(eventTitle)' at \(triggerDate.formatted(date: .abbreviated, time: .shortened))")
            return true
        } catch {
            print("❌ [NotificationManager] Failed to schedule \(identifier): \(error)")
            return false
        }
    }
    
    private var calendar: Calendar {
        var cal = Calendar.current
        cal.timeZone = TimeZone.current
        return cal
    }
    
    // MARK: - State Management
    
    private func storeCurrentState(fingerprints: Set<EventFingerprint>, settings: NotificationSettings) {
        if let data = try? JSONEncoder().encode(Array(fingerprints)) {
            UserDefaults.standard.set(data, forKey: lastScheduledEventsKey)
        }
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: lastNotificationSettingsKey)
        }
    }
    
    private func getStoredFingerprints() -> Set<EventFingerprint> {
        guard let data = UserDefaults.standard.data(forKey: lastScheduledEventsKey),
              let fingerprints = try? JSONDecoder().decode([EventFingerprint].self, from: data) else {
            return Set()
        }
        return Set(fingerprints)
    }
    
    private func getStoredSettings() -> NotificationSettings? {
        guard let data = UserDefaults.standard.data(forKey: lastNotificationSettingsKey),
              let settings = try? JSONDecoder().decode(NotificationSettings.self, from: data) else {
            return nil
        }
        return settings
    }
    
    private func clearStoredState() {
        UserDefaults.standard.removeObject(forKey: lastScheduledEventsKey)
        UserDefaults.standard.removeObject(forKey: lastNotificationSettingsKey)
    }
    
    // MARK: - Validation and Cleanup
    
    private func checkForInvalidNotifications() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let pendingRequests = await center.pendingNotificationRequests()
        let eventNotifications = pendingRequests.filter { $0.identifier.hasPrefix("event_") }
        
        let now = Date()
        let invalidCount = eventNotifications.filter { request in
            guard let trigger = request.trigger as? UNCalendarNotificationTrigger,
                  let nextDate = trigger.nextTriggerDate() else {
                return true // Invalid trigger
            }
            return nextDate <= now // Past date
        }.count
        
        return invalidCount > 0
    }
    
    private func calculateExpectedNotificationCount(for fingerprints: [EventFingerprint]) async -> Int {
        let now = Date()
        let calendar = Calendar.current
        var expectedCount = 0
        
        for fingerprint in fingerprints {
            guard let eventDate = fingerprint.date,
                  eventDate > now else { continue }
            
            if is24HourNotificationEnabled {
                if let notification24h = calendar.date(byAdding: .hour, value: -24, to: eventDate),
                   notification24h > now {
                    expectedCount += 1
                }
            }
            
            if is90MinNotificationEnabled {
                if let notification90min = calendar.date(byAdding: .minute, value: -90, to: eventDate),
                   notification90min > now {
                    expectedCount += 1
                }
            }
        }
        
        return expectedCount
    }
    
    // MARK: - Public Cleanup Methods
    
    func cancelAllEventNotifications() async {
        let center = UNUserNotificationCenter.current()
        let pendingRequests = await center.pendingNotificationRequests()
        let eventNotificationIds = pendingRequests
            .filter { $0.identifier.hasPrefix("event_") }
            .map { $0.identifier }
        
        if !eventNotificationIds.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: eventNotificationIds)
            print("🗑️ [NotificationManager] Cancelled \(eventNotificationIds.count) existing event notifications")
        }
        
        clearStoredState()
    }
    
    func cancelNotifications(for eventId: String) async {
        let identifiersToCancel = [
            "event_\(eventId)_24h",
            "event_\(eventId)_90min"
        ]
        
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiersToCancel)
        print("🗑️ [NotificationManager] Cancelled notifications for event \(eventId)")
    }
    
    // Corner Case 13: Cleanup expired notifications periodically
    func cleanupExpiredNotifications() async {
        let center = UNUserNotificationCenter.current()
        let pendingRequests = await center.pendingNotificationRequests()
        let now = Date()
        
        let expiredIds = pendingRequests.compactMap { request -> String? in
            guard request.identifier.hasPrefix("event_"),
                  let trigger = request.trigger as? UNCalendarNotificationTrigger,
                  let nextDate = trigger.nextTriggerDate(),
                  nextDate <= now else {
                return nil
            }
            return request.identifier
        }
        
        if !expiredIds.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: expiredIds)
            print("🧹 [NotificationManager] Cleaned up \(expiredIds.count) expired notifications")
        }
    }
    
    // MARK: - Debug and Monitoring
    
    private func logScheduledNotifications() async {
        let center = UNUserNotificationCenter.current()
        let pendingRequests = await center.pendingNotificationRequests()
        let eventNotifications = pendingRequests.filter { $0.identifier.hasPrefix("event_") }
        
        print("📋 [NotificationManager] Currently scheduled: \(eventNotifications.count) notifications")
        for request in eventNotifications.prefix(3) {
            if let trigger = request.trigger as? UNCalendarNotificationTrigger,
               let nextDate = trigger.nextTriggerDate() {
                let eventTitle = request.content.userInfo["eventTitle"] as? String ?? "Unknown Event"
                print("   • '\(eventTitle)' at \(nextDate.formatted(date: .abbreviated, time: .shortened))")
            }
        }
        
        if eventNotifications.count > 3 {
            print("   • ... and \(eventNotifications.count - 3) more")
        }
    }
    
    func getScheduledNotificationsCount() async -> Int {
        let center = UNUserNotificationCenter.current()
        let pendingRequests = await center.pendingNotificationRequests()
        return pendingRequests.filter { $0.identifier.hasPrefix("event_") }.count
    }
    
    func getScheduledNotificationDetails() async -> [(eventId: String, eventTitle: String, triggerDate: Date, timeType: String)] {
        let center = UNUserNotificationCenter.current()
        let pendingRequests = await center.pendingNotificationRequests()
        let eventNotifications = pendingRequests.filter { $0.identifier.hasPrefix("event_") }
        
        return eventNotifications.compactMap { request in
            guard let trigger = request.trigger as? UNCalendarNotificationTrigger,
                  let triggerDate = trigger.nextTriggerDate(),
                  let eventId = request.content.userInfo["eventId"] as? String,
                  let eventTitle = request.content.userInfo["eventTitle"] as? String,
                  let timeType = request.content.userInfo["timeType"] as? String else {
                return nil
            }
            
            return (eventId: eventId, eventTitle: eventTitle, triggerDate: triggerDate, timeType: timeType)
        }.sorted { $0.triggerDate < $1.triggerDate }
    }
}
