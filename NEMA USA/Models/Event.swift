//
//  Event.swift
//  NEMA USA
//  Created by Nina on 4/15/25
//  Updated by Arjun on 4/20/2025

import Foundation

struct Event: Identifiable, Decodable, Hashable {
    let id: String
    let title: String
    let description: String?
    let location: String?
    let categoryName: String?
    let eventCatId: Int?
    let imageUrl: String?
    let isRegON: Bool?
    let date: Date?
    let eventLink: String?
    let usesPanthi: Bool?
    let lastUpdatedAt: Date?
    
    enum CodingKeys: String, CodingKey {
        case id, title, description, location, date
        case categoryName = "category_name"
        case eventCatId = "event_cat_id"
        case imageUrl = "image_url"
        case isRegON = "is_reg_on"
        case eventLink = "event_link"
        case lastUpdatedAt = "last_updated_at"
        case usesPanthi = "uses_panthi"
    }

    // Custom Date Formatter for decoding
   static let iso8601DateTimeFormatter: ISO8601DateFormatter = {
       let formatter = ISO8601DateFormatter()
       // Common ISO8601 format, handles timezone offsets like -04:00 or Z
       // By not including .withFractionalSeconds, it becomes more lenient and can parse
       // dates with or without fractional seconds.
       formatter.formatOptions = [.withInternetDateTime]
       return formatter
   }()

    // This one is for date-only strings "yyyy-MM-dd"
    static let iso8601DateOnlyFormatter: DateFormatter = { // Renamed for clarity from your file
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX") // Important for specific formats
        formatter.timeZone = TimeZone(secondsFromGMT: 0) // Assume UTC if not specified, or handle local timezone from string
        return formatter
    }()

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id              = try container.decode(String.self, forKey: .id)
        // It's good to put the ID print right after decoding it, for context in logs
        print("🕵️ Decoding Event ID: \(id)")
        title           = try container.decode(String.self, forKey: .title)
        
        description     = try container.decodeIfPresent(String.self, forKey: .description)
        location        = try container.decodeIfPresent(String.self, forKey: .location)
        categoryName    = try container.decodeIfPresent(String.self, forKey: .categoryName)
        eventCatId      = try container.decodeIfPresent(Int.self, forKey: .eventCatId)
        eventLink       = try container.decodeIfPresent(String.self, forKey: .eventLink)

        // Specific handling for imageUrl
        self.imageUrl = try container.decodeIfPresent(String.self, forKey: .imageUrl)
        print("   imageUrl for Event ID \(id): \(self.imageUrl ?? "nil")")

        // Robust boolean decoding for isRegON
        if let boolValue = try? container.decodeIfPresent(Bool.self, forKey: .isRegON) {
            self.isRegON = boolValue
        } else if let intValue = try? container.decodeIfPresent(Int.self, forKey: .isRegON) {
            self.isRegON = (intValue == 1)
        } else {
            self.isRegON = nil // Or `false` if you prefer a non-nil default and property is non-optional
        }
        print("   isRegON for Event ID \(id): \(String(describing: self.isRegON))")

        // Robust boolean decoding for usesPanthi
        if let boolValue = try? container.decodeIfPresent(Bool.self, forKey: .usesPanthi) {
            self.usesPanthi = boolValue
        } else if let intValue = try? container.decodeIfPresent(Int.self, forKey: .usesPanthi) {
            self.usesPanthi = (intValue == 1)
        } else {
            self.usesPanthi = nil // Or `false`
        }
        print("   usesPanthi for Event ID \(id): \(String(describing: self.usesPanthi))")

        // Date and LastUpdatedAt handling
        if let dateString = try container.decodeIfPresent(String.self, forKey: .date) {
            if !dateString.isEmpty && dateString.lowercased() != "to be announced" {
                if let parsedDate = Event.iso8601DateTimeFormatter.date(from: dateString) {
                    self.date = parsedDate
                } else if let parsedDateOnly = Event.iso8601DateOnlyFormatter.date(from: dateString) {
                    self.date = parsedDateOnly
                } else {
                    print("⚠️ Date string '\(dateString)' could not be parsed for Event ID \(id). Setting date to nil.")
                    self.date = nil
                }
            } else {
                self.date = nil
            }
        } else {
            self.date = nil
        }
        print("   date for Event ID \(id): \(String(describing: self.date))")

        if let lastUpdatedAtString = try container.decodeIfPresent(String.self, forKey: .lastUpdatedAt) {
            if let parsedDate = Event.iso8601DateTimeFormatter.date(from: lastUpdatedAtString) {
                self.lastUpdatedAt = parsedDate
            } else {
                print("⚠️ last_updated_at string '\(lastUpdatedAtString)' could not be parsed for Event ID \(id). Setting lastUpdatedAt to nil.")
                self.lastUpdatedAt = nil
            }
        } else {
            self.lastUpdatedAt = nil
        }
        print("   lastUpdatedAt for Event ID \(id): \(String(describing: self.lastUpdatedAt))")
    }
    
    init(id: String, title: String, description: String?, location: String?,
         categoryName: String?, eventCatId: Int?, imageUrl: String?, isRegON: Bool?, date: Date?, eventLink: String?,
         usesPanthi: Bool?, lastUpdatedAt: Date?) {
        self.id = id
        self.title = title
        self.description = description
        self.location = location
        self.categoryName = categoryName
        self.eventCatId = eventCatId
        self.imageUrl = imageUrl
        self.isRegON = isRegON
        self.date = date
        self.eventLink = eventLink
        self.usesPanthi = usesPanthi
        self.lastUpdatedAt = lastUpdatedAt
    }
    
} // end of file 
