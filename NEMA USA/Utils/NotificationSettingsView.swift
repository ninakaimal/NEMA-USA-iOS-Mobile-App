//
//  NotificationSettingsView.swift
//  NEMA USA
//
//  Created by Nina Kaimal on 7/21/25.
//
import SwiftUI

struct NotificationSettingsView: View {
    @StateObject private var eventRepository = EventRepository()
    @State private var preferences = DatabaseManager.shared.notificationPreferences
    @State private var systemPermissionStatus: String = "Checking..."
    @State private var scheduledNotificationsCount: Int = 0
    @State private var isUpdating = false
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Event Reminders")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Enable Event Notifications", isOn: $preferences.isEnabled)
                            .onChange(of: preferences.isEnabled) { newValue in
                                handleNotificationToggle(newValue)
                            }
                        
                        if preferences.isEnabled {
                            Text("Get reminded about upcoming NEMA events")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text("Turn on to receive notifications before events start")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                if preferences.isEnabled {
                    Section(header: Text("Notification Timing")) {
                        Toggle("24 Hours Before", isOn: $preferences.enable24Hours)
                            .onChange(of: preferences.enable24Hours) { _ in
                                savePreferencesAndRefresh()
                            }
                        
                        Toggle("1.5 Hours Before", isOn: $preferences.enable90Minutes)
                            .onChange(of: preferences.enable90Minutes) { _ in
                                savePreferencesAndRefresh()
                            }
                        
                        Text("Choose when you'd like to be reminded about events")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Section(header: Text("System Status")) {
                    HStack {
                        Text("System Permission")
                        Spacer()
                        Text(systemPermissionStatus)
                            .foregroundColor(systemPermissionStatus == "Granted" ? .green : .orange)
                    }
                    
                    if systemPermissionStatus != "Granted" {
                        Button("Open Settings") {
                            if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(settingsUrl)
                            }
                        }
                        .foregroundColor(.orange)
                    }
                    
                    HStack {
                        Text("Scheduled Notifications")
                        Spacer()
                        Text("\(scheduledNotificationsCount)")
                            .foregroundColor(.secondary)
                    }
                }
                
                if preferences.isEnabled {
                    Section {
                        Button(action: testNotification) {
                            HStack {
                                Image(systemName: "bell.badge")
                                Text("Test Notification")
                            }
                            .foregroundColor(.orange)
                        }
                        .disabled(systemPermissionStatus != "Granted")
                    } footer: {
                        Text("Send a test notification to make sure everything is working")
                            .font(.caption)
                    }
                }
                
                if isUpdating {
                    Section {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Updating notifications...")
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            await loadCurrentStatus()
        }
    }
    
    private func handleNotificationToggle(_ enabled: Bool) {
        Task {
            if enabled {
                // Request permission if enabling notifications
                let granted = await NotificationManager.shared.requestNotificationPermission()
                preferences.isEnabled = granted
                
                if granted {
                    await refreshNotifications()
                }
            } else {
                // Cancel all notifications if disabling
                await NotificationManager.shared.cancelAllEventNotifications()
                scheduledNotificationsCount = 0
            }
            
            savePreferences()
            await updateSystemStatus()
        }
    }
    
    private func savePreferencesAndRefresh() {
        savePreferences()
        
        if preferences.isEnabled {
            Task {
                await refreshNotifications()
                await updateScheduledCount()
            }
        }
    }
    
    private func savePreferences() {
        DatabaseManager.shared.notificationPreferences = preferences
        NotificationManager.shared.areNotificationsEnabled = preferences.isEnabled
        NotificationManager.shared.is24HourNotificationEnabled = preferences.enable24Hours
        NotificationManager.shared.is90MinNotificationEnabled = preferences.enable90Minutes
    }
    
    private func refreshNotifications() async {
        isUpdating = true
        await eventRepository.refreshNotifications()
        await updateScheduledCount()
        isUpdating = false
    }
    
    private func loadCurrentStatus() async {
        await updateSystemStatus()
        await updateScheduledCount()
        
        // Sync preferences from NotificationManager
        preferences.isEnabled = NotificationManager.shared.areNotificationsEnabled
        preferences.enable24Hours = NotificationManager.shared.is24HourNotificationEnabled
        preferences.enable90Minutes = NotificationManager.shared.is90MinNotificationEnabled
    }
    
    private func updateSystemStatus() async {
        let hasPermission = await NotificationManager.shared.checkNotificationPermissions()
        await MainActor.run {
            systemPermissionStatus = hasPermission ? "Granted" : "Denied"
        }
    }
    
    private func updateScheduledCount() async {
        let count = await NotificationManager.shared.getScheduledNotificationsCount()
        await MainActor.run {
            scheduledNotificationsCount = count
        }
    }
    
    private func testNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Test Notification"
        content.body = "NEMA event notifications are working correctly! 🎉"
        content.sound = .default
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
        let request = UNNotificationRequest(identifier: "test_notification", content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ Test notification failed: \(error)")
            } else {
                print("✅ Test notification scheduled")
            }
        }
    }
}

