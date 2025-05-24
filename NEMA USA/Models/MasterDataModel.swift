//
//  MasterDataModel.swift
//  NEMA USA
//  Created by Arjun on 4/15/25.
//  Updated by Sajith on 4/21/25
//

import Foundation

struct UserProfile: Codable, Equatable {
    let id: Int
    let name: String
    let dateOfBirth: String?
    let address: String
    let email: String
    let phone: String
    let comments: String?
    var membershipExpiryDate: String?
    
    enum CodingKeys: String, CodingKey {
            case id, name, dateOfBirth, address, email, phone, comments
            case membershipExpiryDate = "membership_expiry_date"
        }
    // Computed property to check if the user is an active member
    var isMember: Bool {
        guard let expiryDateString = membershipExpiryDate else {
            return false // No expiry date string means not a member
        }

        // Attempt to parse with full ISO8601 datetime format first
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds, .withColonSeparatorInTimeZone]
        if let expiryDate = isoFormatter.date(from: expiryDateString) {
            return expiryDate >= Date() // Member if expiry date is today or in the future
        }

        // Fallback: Attempt to parse with "yyyy-MM-dd" format
        let dateOnlyFormatter = DateFormatter()
        dateOnlyFormatter.dateFormat = "yyyy-MM-dd"
        dateOnlyFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateOnlyFormatter.timeZone = TimeZone(secondsFromGMT: 0) // Assume UTC
        if let expiryDate = dateOnlyFormatter.date(from: expiryDateString) {
            // For date-only, compare against the start of today to include today as active
            return Calendar.current.startOfDay(for: expiryDate) >= Calendar.current.startOfDay(for: Date())
        }
        
        print("⚠️ [UserProfile] Could not parse membershipExpiryDate: \(expiryDateString)")
        return false // Could not parse the date string
    }
}

struct FamilyMember: Identifiable, Codable {
    let id: Int
    var name: String
    var relationship: String
    var email: String?
    var dob: String?
    var phone: String?
}
