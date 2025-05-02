//
//  Event.swift
//  NEMA USA
//  Created by Nina on 4/15/25
//  Updated by Arjun on 4/20/2025

import Foundation

struct Event: Identifiable, Decodable {
    let id: String
    let title: String
    let description: String
    let location: String
    let category: String
    let imageUrl: String
    let isTBD: Bool
    let isRegON: Bool
    let date: Date?
    let eventLink: String?

    enum CodingKeys: String, CodingKey {
        case id, title, description, location, category, imageUrl, date, isTBD, isRegON
        case eventLink = "eventlink"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id          = try container.decode(String.self, forKey: .id)
        title       = try container.decode(String.self, forKey: .title)
        description = try container.decode(String.self, forKey: .description)
        location    = try container.decode(String.self, forKey: .location)
        category    = try container.decode(String.self, forKey: .category)
        imageUrl    = try container.decode(String.self, forKey: .imageUrl)
        isTBD       = try container.decode(Bool.self,   forKey: .isTBD)
        isRegON     = try container.decodeIfPresent(Bool.self, forKey: .isRegON) ?? false
        eventLink   = try container.decodeIfPresent(String.self, forKey: .eventLink)
        
        // Allow "To be announced" or null to be decoded as nil
        if isTBD {
            date = nil
        } else if let dateString = try? container.decodeIfPresent(String.self, forKey: .date),
                  let d = ISO8601DateFormatter().date(from: dateString) {
            date = d
        } else {
            date = nil
        }
    }
}

