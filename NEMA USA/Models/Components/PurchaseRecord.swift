//
//  PurchaseRecord.swift
//  NEMA USA
//  Created by Sajith on 6/18/25.
//

import Foundation

struct PurchaseRecord: Identifiable, Codable, Hashable {
    let recordId: String
    let type: String // "Ticket Purchase" or "Program Registration"
    let purchaseDate: Date
    let eventDate: Date?
    let eventName: String
    let title: String
    let displayAmount: String
    let status: String
    let detailId: Int
    
    var id: String { recordId }
    
    enum CodingKeys: String, CodingKey {
        case recordId, type, eventName, title, status
        case purchaseDate = "purchaseDate"
        case eventDate = "eventDate"
        case displayAmount = "displayAmount"
        case detailId = "detailId"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        recordId = try container.decode(String.self, forKey: .recordId)
        type = try container.decode(String.self, forKey: .type)
        eventName = try container.decode(String.self, forKey: .eventName)
        title = try container.decode(String.self, forKey: .title)
        displayAmount = try container.decode(String.self, forKey: .displayAmount)
        status = try container.decode(String.self, forKey: .status)
        detailId = try container.decode(Int.self, forKey: .detailId)
        
        // Parse dates using ISO8601 format
        let purchaseDateString = try container.decode(String.self, forKey: .purchaseDate)
        let eventDateString = try container.decodeIfPresent(String.self, forKey: .eventDate)
        
        let formatter = ISO8601DateFormatter()
        guard let parsedPurchaseDate = formatter.date(from: purchaseDateString) else {
            throw DecodingError.dataCorruptedError(forKey: .purchaseDate, in: container, debugDescription: "Invalid date format")
        }
        
        purchaseDate = parsedPurchaseDate
        eventDate = eventDateString.flatMap { formatter.date(from: $0) }
    }
    
    // Manual initializer for Core Data mapping
    init(recordId: String, type: String, purchaseDate: Date, eventDate: Date?, eventName: String, title: String, displayAmount: String, status: String, detailId: Int) {
        self.recordId = recordId
        self.type = type
        self.purchaseDate = purchaseDate
        self.eventDate = eventDate
        self.eventName = eventName
        self.title = title
        self.displayAmount = displayAmount
        self.status = status
        self.detailId = detailId
    }
}
