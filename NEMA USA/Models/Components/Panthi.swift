//
//  Panthi.swift
//  NEMA USA
//
//  Created by Sajith on 5/22/25.
//

import Foundation

struct Panthi: Identifiable, Decodable, Hashable {
    let id: Int
    // let eventId: Int // Not strictly needed if fetched contextually by eventId and not part of API JSON per Panthi object
    let name: String        // e.g., "Slot 1: 10 AM - 12 PM", from TicketPanthi.title
    let description: String?
    let availableSlots: Int // from TicketPanthi.available_count
    let totalSlots: Int?    // from TicketPanthi.seat_capacity
    let lastUpdatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case name // Maps to "name" in API (which we mapped from TicketPanthi.title)
        case description
        case availableSlots = "available_slots"
        case totalSlots = "total_slots"
        case lastUpdatedAt = "last_updated_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(Int.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        availableSlots = try container.decode(Int.self, forKey: .availableSlots)
        totalSlots = try container.decodeIfPresent(Int.self, forKey: .totalSlots)

        // Date Decoding for lastUpdatedAt
        // Ideally, use a shared static formatter like Event.iso8601DateTimeFormatter
        // For copy-paste, defining it locally:
        let dateTimeFormatter = ISO8601DateFormatter()
        dateTimeFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds, .withColonSeparatorInTimeZone]

        let lastUpdatedAtString = try container.decode(String.self, forKey: .lastUpdatedAt)
        if let date = dateTimeFormatter.date(from: lastUpdatedAtString) {
            self.lastUpdatedAt = date
        } else {
            throw DecodingError.dataCorruptedError(forKey: .lastUpdatedAt, in: container, debugDescription: "Date string '\(lastUpdatedAtString)' for lastUpdatedAt does not match expected ISO8601 format.")
        }
    }
}
