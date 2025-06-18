//
//  PurchaseRecord.swift
//  NEMA USA
//  Created by Sajith on 6/18/25.
//

import Foundation

// Model for the main list view in "My Events"
struct PurchaseRecord: Codable, Identifiable, Hashable {
    var id: String { recordId }
    let recordId: String
    let type: String
    let purchaseDate: Date
    let eventDate: Date? // Used for sorting and segmentation
    let eventName: String
    let title: String
    let displayAmount: String
    let status: String
    let detailId: Int
}

// Model for the Ticket Purchase Detail View response
struct TicketPurchaseDetailResponse: Codable {
    let purchase: TicketPurchase
    let pdfUrl: String?

    enum CodingKeys: String, CodingKey {
        case purchase
        case pdfUrl = "pdf_url"
    }
}

// Represents a ticket purchase transaction
struct TicketPurchase: Codable {
    let id: Int
    let name: String
    let email: String
    let phone: String
    let totalAmount: String
    let details: [TicketPurchaseDetailItem]
    let panthi: Panthi?

    enum CodingKeys: String, CodingKey {
        case id, name, email, phone, details, panthi
        case totalAmount = "total_amount"
    }
}

// Represents a line item within a ticket purchase
struct TicketPurchaseDetailItem: Codable, Identifiable {
    var id: Int { ticketType.id }
    let no: Int // quantity
    let amount: String // The stored price per item
    let ticketType: EventTicketType

    enum CodingKeys: String, CodingKey {
        case no, amount
        case ticketType = "ticket_type"
    }
}
