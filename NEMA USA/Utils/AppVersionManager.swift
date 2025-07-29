//
//  AppVersionManager.swift
//  NEMA USA
//
//  Created by Arjun Kaimal on 7/28/25.
//
import Foundation
import UIKit

// MARK: - Data Models

struct AppStoreVersionInfo: Codable {
    let version: String
    let trackId: Int
    let trackViewUrl: String
    let releaseNotes: String?
    let currentVersionReleaseDate: String?
    
    private enum CodingKeys: String, CodingKey {
        case version
        case trackId
        case trackViewUrl
        case releaseNotes
        case currentVersionReleaseDate
    }
}

struct AppStoreResponse: Codable {
    let resultCount: Int
    let results: [AppStoreVersionInfo]
}

enum UpdateType: Equatable {
    case none
    case optional(AppStoreVersionInfo)
    case mandatory(AppStoreVersionInfo)
    
    static func == (lhs: UpdateType, rhs: UpdateType) -> Bool {
        switch (lhs, rhs) {
        case (.none, .none):
            return true
        case (.optional(let lhsInfo), .optional(let rhsInfo)):
            return lhsInfo.version == rhsInfo.version && lhsInfo.trackId == rhsInfo.trackId
        case (.mandatory(let lhsInfo), .mandatory(let rhsInfo)):
            return lhsInfo.version == rhsInfo.version && lhsInfo.trackId == rhsInfo.trackId
        default:
            return false
        }
    }
}

enum VersionCheckError: Error, LocalizedError {
    case networkError(String)
    case invalidResponse
    case noAppFound
    case parseError(String)
    case unknownError(String)
    
    var errorDescription: String? {
        switch self {
        case .networkError(let message):
            return "Network error: \(message)"
        case .invalidResponse:
            return "Invalid response from App Store"
        case .noAppFound:
            return "App not found in App Store"
        case .parseError(let message):
            return "Failed to parse version info: \(message)"
        case .unknownError(let message):
            return "Unknown error: \(message)"
        }
    }
}

// MARK: - Configuration

struct VersionCheckConfig {
    let bundleId: String
    let mandatoryVersions: Set<String> // Versions that require mandatory updates
    let skipVersions: Set<String> // Versions to skip (user chose "remind later")
    let checkInterval: TimeInterval // How often to check (in seconds)
    let timeoutInterval: TimeInterval // Network timeout
    
    static let `default` = VersionCheckConfig(
        bundleId: Bundle.main.bundleIdentifier ?? "com.nemausa.app",
        mandatoryVersions: [], // Can be populated from server or hardcoded
        skipVersions: [],
        checkInterval: 24 * 60 * 60, // 24 hours
        timeoutInterval: 15.0 // 15 seconds
    )
}

// MARK: - Main Manager Class

final class AppVersionManager: ObservableObject {
    static let shared = AppVersionManager()
    
    // MARK: - Properties
    
    @Published var updateType: UpdateType = .none
    @Published var isCheckingVersion = false
    @Published var lastCheckDate: Date?
    @Published var lastError: VersionCheckError?
    
    internal var config: VersionCheckConfig
    private let session: URLSession
    
    // UserDefaults keys - made internal for extension access
    internal let lastCheckDateKey = "AppVersionManager.lastCheckDate"
    internal let skippedVersionsKey = "AppVersionManager.skippedVersions"
    internal let mandatoryVersionsKey = "AppVersionManager.mandatoryVersions"
    
    // MARK: - Initialization
    
    private init(config: VersionCheckConfig = .default) {
        self.config = config
        
        // Configure URLSession with timeout
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = config.timeoutInterval
        configuration.timeoutIntervalForResource = config.timeoutInterval * 2
        self.session = URLSession(configuration: configuration)
        
        // Load persisted data
        loadPersistedData()
    }
    
    // MARK: - Public Methods
    
    /// Check for app updates (call this from app launch)
    func checkForUpdates(forced: Bool = false) async {
        // Don't check if already checking
        guard !isCheckingVersion else { return }
        
        // Check if we should skip this check (unless forced)
        if !forced && !shouldCheckForUpdates() {
            print("📱 [AppVersionManager] Skipping version check (too recent)")
            return
        }
        
        await MainActor.run {
            isCheckingVersion = true
            lastError = nil
        }
        
        do {
            let versionInfo = try await fetchAppStoreVersion()
            let currentVersion = getCurrentAppVersion()
            let updateType = determineUpdateType(current: currentVersion, available: versionInfo)
            
            await MainActor.run {
                self.updateType = updateType
                self.lastCheckDate = Date()
                self.isCheckingVersion = false
                self.persistData()
            }
            
            print("✅ [AppVersionManager] Version check completed. Current: \(currentVersion), Available: \(versionInfo.version), Update: \(updateType)")
            
        } catch let error as VersionCheckError {
            await MainActor.run {
                self.lastError = error
                self.isCheckingVersion = false
            }
            print("❌ [AppVersionManager] Version check failed: \(error.localizedDescription)")
        } catch {
            let versionError = VersionCheckError.unknownError(error.localizedDescription)
            await MainActor.run {
                self.lastError = versionError
                self.isCheckingVersion = false
            }
            print("❌ [AppVersionManager] Unexpected error: \(error)")
        }
    }
    
    /// Mark a version as skipped (user chose "remind later")
    func skipVersion(_ version: String) {
        var skippedVersions = getSkippedVersions()
        skippedVersions.insert(version)
        UserDefaults.standard.set(Array(skippedVersions), forKey: skippedVersionsKey)
        
        // Reset update type if we're skipping the current available version
        if case .optional(let versionInfo) = updateType, versionInfo.version == version {
            updateType = .none
        }
        
        print("⏭️ [AppVersionManager] Skipped version \(version)")
    }
    
    /// Open App Store for update
    func openAppStore() {
        guard case .optional(let versionInfo) = updateType,
              let url = URL(string: versionInfo.trackViewUrl) else {
            print("❌ [AppVersionManager] No valid App Store URL available")
            return
        }
        
        DispatchQueue.main.async {
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url) { success in
                    print(success ? "✅ [AppVersionManager] Opened App Store" : "❌ [AppVersionManager] Failed to open App Store")
                }
            }
        }
    }
    
    /// Force open App Store (for mandatory updates)
    func forceOpenAppStore() {
        guard case .mandatory(let versionInfo) = updateType,
              let url = URL(string: versionInfo.trackViewUrl) else {
            print("❌ [AppVersionManager] No valid App Store URL for mandatory update")
            return
        }
        
        DispatchQueue.main.async {
            UIApplication.shared.open(url, options: [:]) { success in
                print(success ? "✅ [AppVersionManager] Opened App Store for mandatory update" : "❌ [AppVersionManager] Failed to open App Store for mandatory update")
            }
        }
    }
    
    /// Add a version to mandatory list (can be called from server config)
    func addMandatoryVersion(_ version: String) {
        var mandatoryVersions = getMandatoryVersions()
        mandatoryVersions.insert(version)
        UserDefaults.standard.set(Array(mandatoryVersions), forKey: mandatoryVersionsKey)
        
        // Re-evaluate current update type
        if case .optional(let versionInfo) = updateType, mandatoryVersions.contains(versionInfo.version) {
            updateType = .mandatory(versionInfo)
        }
        
        print("🚨 [AppVersionManager] Added mandatory version: \(version)")
    }
    
    // MARK: - Private Methods
    
    private func loadPersistedData() {
        lastCheckDate = UserDefaults.standard.object(forKey: lastCheckDateKey) as? Date
    }
    
    private func persistData() {
        if let lastCheckDate = lastCheckDate {
            UserDefaults.standard.set(lastCheckDate, forKey: lastCheckDateKey)
        }
    }
    
    private func shouldCheckForUpdates() -> Bool {
        guard let lastCheck = lastCheckDate else { return true }
        return Date().timeIntervalSince(lastCheck) >= config.checkInterval
    }
    
    internal func getCurrentAppVersion() -> String {
        return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
    
    private func getSkippedVersions() -> Set<String> {
        let array = UserDefaults.standard.array(forKey: skippedVersionsKey) as? [String] ?? []
        return Set(array)
    }
    
    private func getMandatoryVersions() -> Set<String> {
        let array = UserDefaults.standard.array(forKey: mandatoryVersionsKey) as? [String] ?? []
        return array.isEmpty ? config.mandatoryVersions : Set(array)
    }
    
    private func fetchAppStoreVersion() async throws -> AppStoreVersionInfo {
        let urlString = "https://itunes.apple.com/lookup?bundleId=\(config.bundleId)"
        
        guard let url = URL(string: urlString) else {
            throw VersionCheckError.invalidResponse
        }
        
        do {
            let (data, response) = try await session.data(from: url)
            
            // Check HTTP response
            guard let httpResponse = response as? HTTPURLResponse else {
                throw VersionCheckError.invalidResponse
            }
            
            guard (200...299).contains(httpResponse.statusCode) else {
                throw VersionCheckError.networkError("HTTP \(httpResponse.statusCode)")
            }
            
            // Parse JSON
            let decoder = JSONDecoder()
            let appStoreResponse = try decoder.decode(AppStoreResponse.self, from: data)
            
            guard let versionInfo = appStoreResponse.results.first else {
                throw VersionCheckError.noAppFound
            }
            
            return versionInfo
            
        } catch let error as VersionCheckError {
            throw error
        } catch let decodingError as DecodingError {
            throw VersionCheckError.parseError(decodingError.localizedDescription)
        } catch {
            // Handle network errors gracefully
            if (error as NSError).domain == NSURLErrorDomain {
                let nsError = error as NSError
                switch nsError.code {
                case NSURLErrorTimedOut:
                    throw VersionCheckError.networkError("Request timed out")
                case NSURLErrorNotConnectedToInternet:
                    throw VersionCheckError.networkError("No internet connection")
                case NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost:
                    throw VersionCheckError.networkError("Cannot connect to App Store")
                default:
                    throw VersionCheckError.networkError("Network error: \(nsError.localizedDescription)")
                }
            }
            throw VersionCheckError.unknownError(error.localizedDescription)
        }
    }
    
    private func determineUpdateType(current: String, available: AppStoreVersionInfo) -> UpdateType {
        // Compare versions using semantic versioning
        let comparison = compareVersions(current, available.version)
        
        guard comparison == .orderedAscending else {
            return .none // Current version is same or newer
        }
        
        // Check if this version was skipped by user
        let skippedVersions = getSkippedVersions()
        let mandatoryVersions = getMandatoryVersions()
        
        if mandatoryVersions.contains(available.version) {
            return .mandatory(available)
        } else if skippedVersions.contains(available.version) {
            return .none // User chose to skip this version
        } else {
            return .optional(available)
        }
    }
    
    private func compareVersions(_ version1: String, _ version2: String) -> ComparisonResult {
        let v1Components = version1.split(separator: ".").compactMap { Int($0) }
        let v2Components = version2.split(separator: ".").compactMap { Int($0) }
        
        let maxLength = max(v1Components.count, v2Components.count)
        
        for i in 0..<maxLength {
            let v1Value = i < v1Components.count ? v1Components[i] : 0
            let v2Value = i < v2Components.count ? v2Components[i] : 0
            
            if v1Value < v2Value {
                return .orderedAscending
            } else if v1Value > v2Value {
                return .orderedDescending
            }
        }
        
        return .orderedSame
    }
}

// MARK: - Convenience Extensions

extension AppVersionManager {
    var hasUpdate: Bool {
        switch updateType {
        case .none:
            return false
        case .optional, .mandatory:
            return true
        }
    }
    
    var isMandatoryUpdate: Bool {
        switch updateType {
        case .mandatory:
            return true
        case .none, .optional:
            return false
        }
    }
    
    var availableVersion: String? {
        switch updateType {
        case .none:
            return nil
        case .optional(let info), .mandatory(let info):
            return info.version
        }
    }
    
    var releaseNotes: String? {
        switch updateType {
        case .none:
            return nil
        case .optional(let info), .mandatory(let info):
            return info.releaseNotes
        }
    }
}
