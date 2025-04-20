//
//  DatabaseManager.swift
//  NEMA USA
//  Created by Nina on 4/16/25.
//

import Foundation

/// A simple wrapper around UserDefaults to persist auth tokens and the current user profile.
final class DatabaseManager {
    static let shared = DatabaseManager()
    private init() {}

    private let defaults  = UserDefaults.standard
    private let tokenKey  = "authToken"
    private let userKey   = "currentUser"

    // MARK: – Auth Token

    func saveToken(_ token: String) {
        defaults.set(token, forKey: tokenKey)
    }

    var authToken: String? {
        defaults.string(forKey: tokenKey)
    }

    func clearSession() {
        defaults.removeObject(forKey: tokenKey)
        defaults.removeObject(forKey: userKey)
    }

    // MARK: – Current UserProfile

    /// Persist the current UserProfile
    func saveUser(_ profile: UserProfile) {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        defaults.set(data, forKey: userKey)
    }

    /// Retrieve the current UserProfile (if any)
    var currentUser: UserProfile? {
        guard
            let data = defaults.data(forKey: userKey),
            let profile = try? JSONDecoder().decode(UserProfile.self, from: data)
        else {
            return nil
        }
        return profile
    }
}
