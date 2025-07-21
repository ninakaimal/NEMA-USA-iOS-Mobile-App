// DatabaseManager.swift
// NEMA USA
// Created by Nina on 4/16/25.
// Updated by Sajith on 4/21/25
// Updated by Nina on 7/21/25 - Added notification preferences

import Foundation

/// (Laravel scraping session & JSON API JWT), refresh tokens, the current
/// user profile, and the family list.
final class DatabaseManager {
    static let shared = DatabaseManager()
    private init() {}
    private let defaults         = UserDefaults.standard
    private let tokenKey         = "authToken"

    // Key for Laravel (HTML-scraping) session token
    private let laravelSessionKey      = "laravelSessionToken"
    // Key for JSON-API JWT token
    private let jwtApiTokenKey         = "jwtApiToken"

    // Key for refresh token (JSON API)
    private let refreshTokenKey        = "refreshToken"
    // Key for cached UserProfile
    private let userKey                = "currentUser"
    // Key for cached family list
    private let familyKey              = "familyList"

    // MARK: - Notification Settings
    private let notificationPreferencesKey = "notificationPreferences"
    
    struct NotificationPreferences: Codable {
        var isEnabled: Bool = false
        var enable24Hours: Bool = true
        var enable90Minutes: Bool = true
        var hasRequestedPermission: Bool = false
    }
    
    var notificationPreferences: NotificationPreferences {
        get {
            guard let data = defaults.data(forKey: notificationPreferencesKey),
                  let prefs = try? JSONDecoder().decode(NotificationPreferences.self, from: data) else {
                return NotificationPreferences()
            }
            return prefs
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: notificationPreferencesKey)
            }
        }
    }

    // MARK: – Laravel scraping session token

    /// Store the Laravel session token (e.g. "LARAVEL_SESSION")
    func saveLaravelSessionToken(_ token: String) {
        defaults.set(token, forKey: laravelSessionKey)
    }
    /// Retrieve the Laravel session token
    var laravelSessionToken: String? {
        defaults.string(forKey: laravelSessionKey)
    }

    // MARK: – JSON API JWT token

    /// Store the JWT issued by your JSON backend
    func saveJwtApiToken(_ token: String) {
        defaults.set(token, forKey: jwtApiTokenKey)
    }
    /// Retrieve the JWT for JSON API calls (PayPal endpoints, etc.)
    var jwtApiToken: String? {
        defaults.string(forKey: jwtApiTokenKey)
    }

    // MARK: – Refresh Token

    func saveRefreshToken(_ token: String) {
        defaults.set(token, forKey: refreshTokenKey)
    }
    var refreshToken: String? {
        defaults.string(forKey: refreshTokenKey)
    }

    // MARK: – Current UserProfile

    func saveUser(_ profile: UserProfile) {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        defaults.set(data, forKey: userKey)
    }
    var currentUser: UserProfile? {
        guard
            let data    = defaults.data(forKey: userKey),
            let profile = try? JSONDecoder().decode(UserProfile.self, from: data)
        else { return nil }
        return profile
    }

    // MARK: – Family List Persistence

    /// Persist the current family array
    func saveFamily(_ members: [FamilyMember]) {
        guard let data = try? JSONEncoder().encode(members) else { return }
        defaults.set(data, forKey: familyKey)
    }
    /// Retrieve the cached family array (if any)
    var currentFamily: [FamilyMember]? {
        guard
            let data    = defaults.data(forKey: familyKey),
            let members = try? JSONDecoder().decode([FamilyMember].self, from: data)
        else { return nil }
        return members
    }

    // MARK: – Clear All Session Data

    /// Remove all stored session tokens, profile, and family data
    func clearSession() {
        defaults.removeObject(forKey: laravelSessionKey)
        defaults.removeObject(forKey: jwtApiTokenKey)
        defaults.removeObject(forKey: refreshTokenKey)
        defaults.removeObject(forKey: userKey)
        defaults.removeObject(forKey: familyKey)
        defaults.removeObject(forKey: "membershipExpiryDate")
        defaults.removeObject(forKey: "userId")
        print("[DatabaseManager] Cleared all session and user-specific AppStorage keys.")
    }
}
