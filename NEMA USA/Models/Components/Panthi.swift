//
//  Panthi.swift
//  NEMA USA
//
//  Created by Sajith on 5/22/25.
//

import Foundation

struct Panthi: Identifiable, Decodable, Hashable {
    let id: Int
    let name: String
    let description: String?
    let availableSlots: Int
    let totalSlots: Int?
    let lastUpdatedAt: Date // Swift property is camelCase

    // CodingKeys correctly map snake_case JSON keys to camelCase Swift properties.
    // This is good practice.
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case availableSlots = "available_slots"
        case totalSlots = "total_slots"
        case lastUpdatedAt = "last_updated_at" // JSON key is snake_case
    }
}
