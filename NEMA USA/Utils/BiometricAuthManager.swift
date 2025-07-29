//
//  BiometricAuthManager.swift
//  NEMA USA
//
//  Created by Nina Kaimal on 7/29/25.
//  Handle FaceID/TouchID authentication
//

import Foundation
import LocalAuthentication
import UIKit

enum BiometricType {
    case none
    case touchID
    case faceID
    case opticID // For newer devices
    
    var displayName: String {
        switch self {
        case .none:
            return "Biometric Authentication"
        case .touchID:
            return "Touch ID"
        case .faceID:
            return "Face ID"
        case .opticID:
            return "Optic ID"
        }
    }
    
    var iconName: String {
        switch self {
        case .none:
            return "touchid"
        case .touchID:
            return "touchid"
        case .faceID:
            return "faceid"
        case .opticID:
            return "opticid"
        }
    }
}

enum BiometricError: Error, LocalizedError {
    case notAvailable
    case notEnrolled
    case lockout
    case cancelled
    case failed
    case unknown(String)
    
    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "Biometric authentication is not available on this device"
        case .notEnrolled:
            return "No biometric authentication is set up on this device"
        case .lockout:
            return "Biometric authentication is locked. Please try again later"
        case .cancelled:
            return "Authentication was cancelled"
        case .failed:
            return "Authentication failed"
        case .unknown(let message):
            return message
        }
    }
}

final class BiometricAuthManager: ObservableObject {
    static let shared = BiometricAuthManager()
    
    private let context = LAContext()
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Get the type of biometric authentication available
    func getBiometricType() -> BiometricType {
        var error: NSError?
        
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return .none
        }
        
        switch context.biometryType {
        case .faceID:
            return .faceID
        case .touchID:
            return .touchID
        case .opticID:
            if #available(iOS 17.0, *) {
                return .opticID
            } else {
                return .faceID // Fallback for older iOS versions
            }
        case .none:
            return .none
        @unknown default:
            return .none
        }
    }
    
    /// Check if biometric authentication is available and set up
    func isBiometricAvailable() -> Bool {
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }
    
    /// Check if biometric authentication is enrolled (user has set up Face/Touch ID)
    func isBiometricEnrolled() -> Bool {
        var error: NSError?
        let canEvaluate = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        
        if let error = error {
            switch error.code {
            case LAError.biometryNotEnrolled.rawValue:
                return false
            default:
                return false
            }
        }
        
        return canEvaluate
    }
    
    /// Authenticate using biometric authentication
    func authenticate(reason: String) async -> Result<Bool, BiometricError> {
        // Create a fresh context for each authentication attempt
        let authContext = LAContext()
        authContext.localizedFallbackTitle = "Use Passcode"
        authContext.localizedCancelTitle = "Cancel"
        
        // Check if biometric authentication is available
        var error: NSError?
        guard authContext.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            if let error = error {
                return .failure(mapLAError(error))
            }
            return .failure(.notAvailable)
        }
        
        do {
            let success = try await authContext.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )
            
            if success {
                print("✅ [BiometricAuthManager] Authentication successful")
                return .success(true)
            } else {
                print("❌ [BiometricAuthManager] Authentication failed")
                return .failure(.failed)
            }
        } catch {
            print("❌ [BiometricAuthManager] Authentication error: \(error)")
            let biometricError = mapLAError(error as NSError)
            return .failure(biometricError)
        }
    }
    
    /// Authenticate with fallback to device passcode
    func authenticateWithPasscode(reason: String) async -> Result<Bool, BiometricError> {
        let authContext = LAContext()
        authContext.localizedFallbackTitle = "Use Passcode"
        authContext.localizedCancelTitle = "Cancel"
        
        var error: NSError?
        guard authContext.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            if let error = error {
                return .failure(mapLAError(error))
            }
            return .failure(.notAvailable)
        }
        
        do {
            let success = try await authContext.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: reason
            )
            
            if success {
                print("✅ [BiometricAuthManager] Authentication with passcode successful")
                return .success(true)
            } else {
                print("❌ [BiometricAuthManager] Authentication with passcode failed")
                return .failure(.failed)
            }
        } catch {
            print("❌ [BiometricAuthManager] Authentication with passcode error: \(error)")
            let biometricError = mapLAError(error as NSError)
            return .failure(biometricError)
        }
    }
    
    // MARK: - Private Methods
    
    private func mapLAError(_ error: NSError) -> BiometricError {
        switch error.code {
        case LAError.biometryNotAvailable.rawValue:
            return .notAvailable
        case LAError.biometryNotEnrolled.rawValue:
            return .notEnrolled
        case LAError.biometryLockout.rawValue:
            return .lockout
        case LAError.userCancel.rawValue:
            return .cancelled
        case LAError.userFallback.rawValue:
            return .cancelled
        case LAError.authenticationFailed.rawValue:
            return .failed
        case LAError.systemCancel.rawValue:
            return .cancelled
        case LAError.appCancel.rawValue:
            return .cancelled
        case LAError.invalidContext.rawValue:
            return .failed
        case LAError.notInteractive.rawValue:
            return .failed
        default:
            return .unknown(error.localizedDescription)
        }
    }
}
