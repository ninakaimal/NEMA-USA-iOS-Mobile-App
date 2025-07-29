//
//  VersionConfigHelper.swift
//  NEMA USA
//
//  Created by Nina Kaimal on 7/28/25.
//

import Foundation

// MARK: - Configuration Management

extension VersionCheckConfig {
    /// Load configuration from Info.plist with fallback to defaults
    static func fromPlist() -> VersionCheckConfig {
        guard let plistPath = Bundle.main.path(forResource: "NEMA-USA-Info", ofType: "plist"),
              let plistData = FileManager.default.contents(atPath: plistPath),
              let plist = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any],
              let versionConfig = plist["VersionCheckConfig"] as? [String: Any] else {
            print("📱 [VersionConfig] Using default configuration")
            return .default
        }
        
        let bundleId = Bundle.main.bundleIdentifier ?? "com.nemausa.app"
        let checkInterval = TimeInterval(versionConfig["CheckInterval"] as? Int ?? 86400) // 24 hours
        let timeoutInterval = TimeInterval(versionConfig["TimeoutInterval"] as? Int ?? 15) // 15 seconds
        let mandatoryVersionsArray = versionConfig["MandatoryVersions"] as? [String] ?? []
        let mandatoryVersions = Set(mandatoryVersionsArray)
        
        print("📱 [VersionConfig] Loaded from plist - Check interval: \(checkInterval)s, Mandatory versions: \(mandatoryVersions)")
        
        return VersionCheckConfig(
            bundleId: bundleId,
            mandatoryVersions: mandatoryVersions,
            skipVersions: [],
            checkInterval: checkInterval,
            timeoutInterval: timeoutInterval
        )
    }
    
    /// Load configuration from a remote server (call this periodically)
    static func fromServer() async -> VersionCheckConfig? {
        // This would typically fetch from your backend API
        // For now, return nil to use local config
        
        // Example implementation:
        /*
        do {
            let url = URL(string: "https://nemausa.org/api/v1/app-config")!
            let (data, _) = try await URLSession.shared.data(from: url)
            let serverConfig = try JSONDecoder().decode(ServerVersionConfig.self, from: data)
            
            return VersionCheckConfig(
                bundleId: Bundle.main.bundleIdentifier ?? "com.nemausa.app",
                mandatoryVersions: Set(serverConfig.mandatoryVersions),
                skipVersions: [],
                checkInterval: TimeInterval(serverConfig.checkIntervalHours * 3600),
                timeoutInterval: TimeInterval(serverConfig.timeoutSeconds)
            )
        } catch {
            print("❌ [VersionConfig] Failed to load from server: \(error)")
            return nil
        }
        */
        
        return nil
    }
}

// MARK: - Server Configuration Models

struct ServerVersionConfig: Codable {
    let mandatoryVersions: [String]
    let checkIntervalHours: Int
    let timeoutSeconds: Int
    let message: VersionMessages?
}

struct VersionMessages: Codable {
    let optionalUpdateTitle: String?
    let optionalUpdateMessage: String?
    let mandatoryUpdateTitle: String?
    let mandatoryUpdateMessage: String?
}

// MARK: - Enhanced AppVersionManager with Server Config

extension AppVersionManager {
    /// Initialize with server configuration (call this after app setup)
    func configureFromServer() async {
        if let serverConfig = await VersionCheckConfig.fromServer() {
            self.config = serverConfig
            print("✅ [AppVersionManager] Updated configuration from server")
        } else {
            // Fall back to plist configuration
            self.config = VersionCheckConfig.fromPlist()
            print("📱 [AppVersionManager] Using plist configuration")
        }
    }
    
    /// Check if a specific version should be mandatory (useful for server-driven updates)
    func markVersionAsMandatory(_ version: String) {
        addMandatoryVersion(version)
        
        // If this version is currently available as optional, upgrade it to mandatory
        if case .optional(let versionInfo) = updateType, versionInfo.version == version {
            updateType = .mandatory(versionInfo)
            print("🚨 [AppVersionManager] Upgraded version \(version) from optional to mandatory")
        }
    }
    
    /// Get formatted version comparison string for UI
    func getVersionComparisonText() -> String? {
        let currentVersion = getCurrentAppVersion()
        guard let availableVersion = availableVersion else { return nil }
        
        return "Current: v\(currentVersion) → Available: v\(availableVersion)"
    }
    
    /// Check if current version is significantly outdated (more than 2 major versions behind)
    func isSignificantlyOutdated() -> Bool {
        let currentVersion = getCurrentAppVersion()
        guard let availableVersion = availableVersion else { return false }
        
        let currentComponents = currentVersion.split(separator: ".").compactMap { Int($0) }
        let availableComponents = availableVersion.split(separator: ".").compactMap { Int($0) }
        
        guard let currentMajor = currentComponents.first,
              let availableMajor = availableComponents.first else { return false }
        
        return (availableMajor - currentMajor) >= 2
    }
}

// MARK: - Notification Extensions

extension Notification.Name {
    static let didReceiveVersionUpdate = Notification.Name("didReceiveVersionUpdate")
    static let didFailVersionCheck = Notification.Name("didFailVersionCheck")
}

// MARK: - Debug Helpers

#if DEBUG
extension AppVersionManager {
    /// Force set update type for testing
    func debugSetUpdateType(_ type: UpdateType) {
        DispatchQueue.main.async {
            self.updateType = type
        }
    }
    
    /// Simulate network error for testing
    func debugSimulateNetworkError() {
        DispatchQueue.main.async {
            self.lastError = .networkError("Simulated network error for testing")
        }
    }
    
    /// Reset all version check data
    func debugReset() {
        UserDefaults.standard.removeObject(forKey: lastCheckDateKey)
        UserDefaults.standard.removeObject(forKey: skippedVersionsKey)
        UserDefaults.standard.removeObject(forKey: mandatoryVersionsKey)
        
        DispatchQueue.main.async {
            self.updateType = .none
            self.lastCheckDate = nil
            self.lastError = nil
        }
        
        print("🔄 [AppVersionManager] Debug reset completed")
    }
}
#endif
