//
//  KeychainManager.swift
//  NEMA USA
//
//  Created by Nina Kaimal on 7/29/25.
//

import Foundation
import Security

final class KeychainManager {
    static let shared = KeychainManager()
    
    private init() {}
    
    // MARK: - Constants
    
    private let service = "com.nemausa.app.credentials"
    private let emailKey = "user_email"
    private let passwordKey = "user_password"
    
    // MARK: - Public Methods
    
    /// Save email and password to Keychain
    func saveCredentials(email: String, password: String) -> Bool {
        let emailSaved = saveString(email, forKey: emailKey)
        let passwordSaved = saveString(password, forKey: passwordKey)
        
        if emailSaved && passwordSaved {
            print("✅ [KeychainManager] Credentials saved successfully")
            return true
        } else {
            print("❌ [KeychainManager] Failed to save credentials")
            return false
        }
    }
    
    /// Retrieve saved credentials from Keychain
    func getCredentials() -> (email: String, password: String)? {
        guard let email = getString(forKey: emailKey),
              let password = getString(forKey: passwordKey) else {
            print("⚠️ [KeychainManager] No saved credentials found")
            return nil
        }
        
        print("✅ [KeychainManager] Retrieved saved credentials")
        return (email: email, password: password)
    }
    
    /// Delete saved credentials from Keychain
    func deleteCredentials() -> Bool {
        let emailDeleted = deleteItem(forKey: emailKey)
        let passwordDeleted = deleteItem(forKey: passwordKey)
        
        if emailDeleted && passwordDeleted {
            print("✅ [KeychainManager] Credentials deleted successfully")
            return true
        } else {
            print("❌ [KeychainManager] Failed to delete some credentials")
            return false
        }
    }
    
    /// Check if credentials are saved
    func hasCredentials() -> Bool {
        return getString(forKey: emailKey) != nil && getString(forKey: passwordKey) != nil
    }
    
    // MARK: - Private Methods
    
    private func saveString(_ string: String, forKey key: String) -> Bool {
        guard let data = string.data(using: .utf8) else {
            print("❌ [KeychainManager] Failed to convert string to data for key: \(key)")
            return false
        }
        
        // Delete existing item first
        let _ = deleteItem(forKey: key)
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        if status == errSecSuccess {
            return true
        } else {
            print("❌ [KeychainManager] Failed to save \(key). Status: \(status)")
            return false
        }
    }
    
    private func getString(forKey key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecSuccess,
           let data = result as? Data,
           let string = String(data: data, encoding: .utf8) {
            return string
        } else if status != errSecItemNotFound {
            print("❌ [KeychainManager] Failed to retrieve \(key). Status: \(status)")
        }
        
        return nil
    }
    
    private func deleteItem(forKey key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        if status == errSecSuccess || status == errSecItemNotFound {
            return true
        } else {
            print("❌ [KeychainManager] Failed to delete \(key). Status: \(status)")
            return false
        }
    }
}
