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
    var phone: String?
    var dob: String?
    let userId: Int
    let createdAt: String?
    let updatedAt: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case name, fname
        case relationship
        case email
        case phone
        case dob
        case userId = "user_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    // Custom decoder to handle both "name" and "fname"
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(Int.self, forKey: .id)
        relationship = try container.decode(String.self, forKey: .relationship)
        email = try container.decodeIfPresent(String.self, forKey: .email)
        phone = try container.decodeIfPresent(String.self, forKey: .phone)
        dob = try container.decodeIfPresent(String.self, forKey: .dob)
        userId = try container.decodeIfPresent(Int.self, forKey: .userId) ?? 0 // Provide default value
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
        
        // Try "name" first, then "fname" as fallback
        if let nameValue = try container.decodeIfPresent(String.self, forKey: .name) {
            name = nameValue
        } else if let fnameValue = try container.decodeIfPresent(String.self, forKey: .fname) {
            name = fnameValue
        } else {
            throw DecodingError.keyNotFound(CodingKeys.name, DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Neither 'name' nor 'fname' found in JSON"
            ))
        }
    }
    
    // Custom encoder - always encode as "name" when sending to APIs
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)  // Always use "name" when encoding
        try container.encode(relationship, forKey: .relationship)
        try container.encodeIfPresent(email, forKey: .email)
        try container.encodeIfPresent(phone, forKey: .phone)
        try container.encodeIfPresent(dob, forKey: .dob)
        try container.encode(userId, forKey: .userId)
        try container.encodeIfPresent(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(updatedAt, forKey: .updatedAt)
    }
    
    // Manual initializer for creating new instances
    init(id: Int, name: String, relationship: String, email: String? = nil, phone: String? = nil, dob: String? = nil, userId: Int, createdAt: String? = nil, updatedAt: String? = nil) {
        self.id = id
        self.name = name
        self.relationship = relationship
        self.email = email
        self.phone = phone
        self.dob = dob
        self.userId = userId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
