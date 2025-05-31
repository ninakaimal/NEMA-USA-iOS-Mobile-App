//
//  Event.swift
//  NEMA USA
//  Created by Nina on 4/15/25
//  Updated by Arjun on 4/20/2025
//  Updated by Sajith on 5/20/2025 to refactor and simplify code

// Event.swift
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
        case id, title, description, location // Assumes JSON key matches property name for these
        case categoryName = "category_name"
        case eventCatId = "event_cat_id"
        case imageUrl = "image_url"
        case isRegON = "is_reg_on"
        case date // Assuming JSON key is "date"
        case eventLink = "event_link"
        case usesPanthi = "uses_panthi"
        case lastUpdatedAt = "last_updated_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        location = try container.decodeIfPresent(String.self, forKey: .location)
        categoryName = try container.decodeIfPresent(String.self, forKey: .categoryName)
        eventCatId = try container.decodeIfPresent(Int.self, forKey: .eventCatId)
        imageUrl = try container.decodeIfPresent(String.self, forKey: .imageUrl) // Explicitly decode with CodingKey
        eventLink = try container.decodeIfPresent(String.self, forKey: .eventLink)

        // Explicitly use the decoder's date strategy (from NetworkManager)
        date = try container.decodeIfPresent(Date.self, forKey: .date)
        lastUpdatedAt = try container.decodeIfPresent(Date.self, forKey: .lastUpdatedAt)

        // Robust boolean decoding for isRegON
        if container.contains(.isRegON) {
            if let boolValue = try? container.decode(Bool.self, forKey: .isRegON) {
                self.isRegON = boolValue
            } else if let intValue = try? container.decode(Int.self, forKey: .isRegON) {
                self.isRegON = (intValue == 1)
            } else if let stringValue = try? container.decode(String.self, forKey: .isRegON) {
                self.isRegON = (stringValue.lowercased() == "true" || stringValue == "1")
            } else {
                self.isRegON = nil // Or default to false if that makes more sense: false
            }
        } else {
            self.isRegON = nil // Or default to false
        }

        // Robust boolean decoding for usesPanthi
        if container.contains(.usesPanthi) {
            if let boolValue = try? container.decode(Bool.self, forKey: .usesPanthi) {
                self.usesPanthi = boolValue
            } else if let intValue = try? container.decode(Int.self, forKey: .usesPanthi) {
                self.usesPanthi = (intValue == 1)
            } else if let stringValue = try? container.decode(String.self, forKey: .usesPanthi) {
                self.usesPanthi = (stringValue.lowercased() == "true" || stringValue == "1")
            } else {
                self.usesPanthi = nil // Or default to false
            }
        } else {
            self.usesPanthi = nil // Or default to false
        }
        
        // Your detailed logging from the previous version of Event.swift can be re-added here if needed,
        // after each property is assigned, for example:
        // print("   FINAL Event ID \(self.id) - imageUrl: \(self.imageUrl ?? "NIL")")
        // print("   FINAL Event ID \(self.id) - isRegON: \(String(describing: self.isRegON))")
        // etc.
    }

    // Memberwise initializer (keep for manual creation / CoreData mapping)
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
}
