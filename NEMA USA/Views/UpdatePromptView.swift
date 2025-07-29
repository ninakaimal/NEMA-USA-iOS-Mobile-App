//
//  UpdatePromptView.swift
//  NEMA USA
//
//  Created by Nina Kaimal on 7/28/25.
//

import SwiftUI

struct UpdatePromptView: View {
    @ObservedObject var versionManager: AppVersionManager
    @Environment(\.dismiss) private var dismiss
    
    let updateType: UpdateType
    
    init(updateType: UpdateType, versionManager: AppVersionManager = AppVersionManager.shared) {
        self.updateType = updateType
        self.versionManager = versionManager
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // App Icon and Title
                VStack(spacing: 16) {
                    Image("AppIcon") // Make sure this matches your app icon name
                        .resizable()
                        .frame(width: 80, height: 80)
                        .cornerRadius(16)
                        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                    
                    Text(updateTitle)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)
                }
                
                // Update Information
                VStack(spacing: 12) {
                    if let availableVersion = versionManager.availableVersion {
                        HStack {
                            Text("New Version:")
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("v\(availableVersion)")
                                .fontWeight(.semibold)
                                .foregroundColor(.orange)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(10)
                    }
                    
                    Text(updateMessage)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(nil)
                }
                
                // Release Notes (if available)
                if let releaseNotes = versionManager.releaseNotes?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !releaseNotes.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("What's New:")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        ScrollView {
                            Text(releaseNotes)
                                .font(.body)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.leading)
                        }
                        .frame(maxHeight: 120)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                    }
                }
                
                Spacer()
                
                // Action Buttons
                VStack(spacing: 12) {
                    // Update Button
                    Button(action: {
                        handleUpdateTapped()
                    }) {
                        HStack {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.system(size: 20))
                            Text(updateButtonTitle)
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.orange)
                        .cornerRadius(12)
                    }
                    
                    // Secondary Button (only for optional updates)
                    if case .optional = updateType {
                        HStack(spacing: 12) {
                            // Remind Later Button
                            Button(action: {
                                handleRemindLaterTapped()
                            }) {
                                Text("Remind Later")
                                    .fontWeight(.medium)
                                    .foregroundColor(.orange)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 44)
                                    .background(Color.orange.opacity(0.1))
                                    .cornerRadius(10)
                            }
                            
                            // Skip Button
                            Button(action: {
                                handleSkipTapped()
                            }) {
                                Text("Skip")
                                    .fontWeight(.medium)
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 44)
                                    .background(Color(.systemGray5))
                                    .cornerRadius(10)
                            }
                        }
                    }
                }
            }
            .padding(24)
            .navigationBarHidden(isMandatory)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(isMandatory)
            .overlay(
                // Custom cancel button for non-mandatory updates
                Group {
                    if !isMandatory {
                        VStack {
                            HStack {
                                Button("Cancel") {
                                    dismiss()
                                }
                                .foregroundColor(.orange)
                                .padding(.leading, 16)
                                .padding(.top, 8)
                                Spacer()
                            }
                            Spacer()
                        }
                    }
                }
            )
        }
        .interactiveDismissDisabled(isMandatory)
    }
    
    // MARK: - Computed Properties
    
    private var isMandatory: Bool {
        if case .mandatory = updateType {
            return true
        }
        return false
    }
    
    private var updateTitle: String {
        switch updateType {
        case .none:
            return ""
        case .optional:
            return "New Version Available!"
        case .mandatory:
            return "Required Update"
        }
    }
    
    private var updateMessage: String {
        switch updateType {
        case .none:
            return ""
        case .optional:
            return "A new version of NEMA USA is available with improved features and bug fixes. Update now to get the latest experience!"
        case .mandatory:
            return "This update contains important security fixes and is required to continue using the app. Please update now."
        }
    }
    
    private var updateButtonTitle: String {
        switch updateType {
        case .none:
            return ""
        case .optional:
            return "Update Now"
        case .mandatory:
            return "Update Required"
        }
    }
    
    // MARK: - Action Handlers
    
    private func handleUpdateTapped() {
        switch updateType {
        case .none:
            break
        case .optional:
            versionManager.openAppStore()
            dismiss()
        case .mandatory:
            versionManager.forceOpenAppStore()
            // Don't dismiss for mandatory updates - keep showing until they update
        }
    }
    
    private func handleRemindLaterTapped() {
        dismiss()
    }
    
    private func handleSkipTapped() {
        if let version = versionManager.availableVersion {
            versionManager.skipVersion(version)
        }
        dismiss()
    }
}

// MARK: - Error View

struct UpdateErrorView: View {
    let error: VersionCheckError
    let onRetry: () -> Void
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 50))
                .foregroundColor(.orange)
            
            VStack(spacing: 8) {
                Text("Update Check Failed")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text(error.localizedDescription)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            VStack(spacing: 12) {
                Button(action: onRetry) {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Try Again")
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color.orange)
                    .cornerRadius(10)
                }
                
                Button(action: onDismiss) {
                    Text("Continue Without Update")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Color(.systemGray5))
                        .cornerRadius(10)
                }
            }
        }
        .padding(24)
    }
}

// MARK: - Preview

#if DEBUG
struct UpdatePromptView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // Optional Update
            UpdatePromptView(
                updateType: .optional(AppStoreVersionInfo(
                    version: "2.1.0",
                    trackId: 123456789,
                    trackViewUrl: "https://apps.apple.com/app/id123456789",
                    releaseNotes: "• Enhanced event notifications\n• Improved user interface\n• Bug fixes and performance improvements",
                    currentVersionReleaseDate: "2025-07-28T10:00:00Z"
                ))
            )
            .previewDisplayName("Optional Update")
            
            // Mandatory Update
            UpdatePromptView(
                updateType: .mandatory(AppStoreVersionInfo(
                    version: "2.0.0",
                    trackId: 123456789,
                    trackViewUrl: "https://apps.apple.com/app/id123456789",
                    releaseNotes: "• Critical security fixes\n• Required backend compatibility updates",
                    currentVersionReleaseDate: "2025-07-28T10:00:00Z"
                ))
            )
            .previewDisplayName("Mandatory Update")
            
            // Error View
            UpdateErrorView(
                error: .networkError("No internet connection"),
                onRetry: {},
                onDismiss: {}
            )
            .previewDisplayName("Error View")
        }
    }
}
#endif
