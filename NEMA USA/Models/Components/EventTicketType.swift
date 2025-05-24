//
//  EventTicketType.swift
//  NEMA USA
//
//  Created by Sajith on 5/22/25.

import Foundation

struct EventTicketType: Identifiable, Decodable, Hashable {
    let id: Int
    let typeName: String
    let publicPrice: Double
    let memberPrice: Double?
    let earlyBirdPublicPrice: Double?
    let earlyBirdMemberPrice: Double?
    let earlyBirdEndDate: Date?
    let currencyCode: String
    let isTicketTypeMemberExclusive: Bool? // True if this ticket type is ONLY for members
    let lastUpdatedAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case typeName = "type_name"
        case publicPrice = "public_price"
        case memberPrice = "member_price"
        case earlyBirdPublicPrice = "early_bird_public_price"
        case earlyBirdMemberPrice = "early_bird_member_price"
        case earlyBirdEndDate = "early_bird_end_date"
        case currencyCode = "currency_code"
        case isTicketTypeMemberExclusive = "is_ticket_type_member_exclusive"
        case lastUpdatedAt = "last_updated_at"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let decodedId = try? container.decodeIfPresent(Int.self, forKey: .id)
        print("🔍 EventTicketType (ID: \(decodedId ?? -1)) Decoding Keys: \(container.allKeys.map { $0.stringValue })")
        
        id = try container.decode(Int.self, forKey: .id)
        // typeName is non-optional, so if the key is missing, this will (and should) fail.
        // Your raw JSON log shows "type_name" is present.
        typeName = try container.decode(String.self, forKey: .typeName)
        print("   typeName for TicketType ID \(id): \(self.typeName)")

        publicPrice = try container.decode(Double.self, forKey: .publicPrice)
        memberPrice = try container.decodeIfPresent(Double.self, forKey: .memberPrice)
        earlyBirdPublicPrice = try container.decodeIfPresent(Double.self, forKey: .earlyBirdPublicPrice)
        earlyBirdMemberPrice = try container.decodeIfPresent(Double.self, forKey: .earlyBirdMemberPrice)
        currencyCode = try container.decode(String.self, forKey: .currencyCode) // Assuming this is always present

        // Robust boolean decoding for isTicketTypeMemberExclusive
        if let boolValue = try? container.decodeIfPresent(Bool.self, forKey: .isTicketTypeMemberExclusive) {
            self.isTicketTypeMemberExclusive = boolValue
        } else if let intValue = try? container.decodeIfPresent(Int.self, forKey: .isTicketTypeMemberExclusive) {
            self.isTicketTypeMemberExclusive = (intValue == 1)
        } else {
            self.isTicketTypeMemberExclusive = nil // Property is Bool?
        }
        print("   isTicketTypeMemberExclusive for TicketType ID \(id): \(String(describing: self.isTicketTypeMemberExclusive))")

        // Decode earlyBirdEndDate (expects "YYYY-MM-DD" string or null)
        if let earlyBirdEndDateString = try container.decodeIfPresent(String.self, forKey: .earlyBirdEndDate) {
            if !earlyBirdEndDateString.isEmpty {
                // Use the static DateFormatter from Event.swift for consistency if you prefer
                // For this example, defining it locally for clarity if Event.swift isn't directly accessible.
                let dateOnlyFormatter = DateFormatter()
                dateOnlyFormatter.dateFormat = "yyyy-MM-dd"
                dateOnlyFormatter.locale = Locale(identifier: "en_US_POSIX")
                dateOnlyFormatter.timeZone = TimeZone(secondsFromGMT: 0) // Assuming dates are UTC if no timezone in string
                
                if let date = dateOnlyFormatter.date(from: earlyBirdEndDateString) {
                    self.earlyBirdEndDate = date
                } else {
                    print("⚠️ Warning: Could not parse earlyBirdEndDate string '\(earlyBirdEndDateString)' for ticket type ID \(id). Setting to nil.")
                    self.earlyBirdEndDate = nil
                }
            } else {
                self.earlyBirdEndDate = nil // Treat empty string as nil
            }
        } else {
            self.earlyBirdEndDate = nil // Key not present or JSON value is null
        }
        print("   earlyBirdEndDate for TicketType ID \(id): \(String(describing: self.earlyBirdEndDate))")

        // Decode lastUpdatedAt (expects full ISO8601 datetime string from API)
        // Property is non-optional: let lastUpdatedAt: Date
        let lastUpdatedAtString = try container.decode(String.self, forKey: .lastUpdatedAt)
        print("   lastUpdatedAtString for TicketType ID \(id): \"\(lastUpdatedAtString)\"")

        // Use Event's static formatter which is more lenient and known to work for similar strings
        if let date = Event.iso8601DateTimeFormatter.date(from: lastUpdatedAtString) {
            self.lastUpdatedAt = date
        } else {
            // As a fallback, try the more specific formatter that was in NetworkManager
            let specificFormatter = ISO8601DateFormatter()
            specificFormatter.formatOptions = [
                .withInternetDateTime, .withDashSeparatorInDate,
                .withColonSeparatorInTime, .withColonSeparatorInTimeZone
            ]
            if let specificDate = specificFormatter.date(from: lastUpdatedAtString) {
                self.lastUpdatedAt = specificDate
                print("     ⚠️ Parsed last_updated_at for TicketType ID \(id) with specific local formatter.")
            } else {
                print("     ❌ FAILED to parse last_updated_at string '\(lastUpdatedAtString)' for TicketType ID \(id) with all formatters.")
                throw DecodingError.dataCorruptedError(
                    forKey: .lastUpdatedAt, in: container,
                    debugDescription: "Date string '\(lastUpdatedAtString)' for lastUpdatedAt does not match expected ISO8601 formats."
                )
            }
        }
        print("   lastUpdatedAt for TicketType ID \(id): \(self.lastUpdatedAt)")
    }
}
