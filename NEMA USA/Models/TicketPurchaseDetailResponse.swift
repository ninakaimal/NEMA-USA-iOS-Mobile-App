//
//  TicketPurchaseDetailResponse.swift
//  NEMA USA
//
//  Created by Nina Kaimal on 6/27/25.
//
import Foundation

// MARK: - Ticket Purchase Detail Response
struct TicketPurchaseDetailResponse: Codable {
    let purchase: TicketPurchase
    let pdfUrl: String?
    
    enum CodingKeys: String, CodingKey {
        case purchase
        case pdfUrl = "pdf_url"
    }
}

struct TicketPurchase: Codable {
    let id: Int
    let name: String
    let email: String
    let phone: String
    let totalAmount: Double
    let details: [TicketPurchaseDetail]
    let panthi: TicketPanthi?
    
    enum CodingKeys: String, CodingKey {
        case id, name, email, phone, details, panthi
        case totalAmount = "total_amount"
    }
}

struct TicketPurchaseDetail: Codable {
    let no: Int
    let amount: Double
    let ticketType: TicketTypeForPurchase
    
    enum CodingKeys: String, CodingKey {
        case no, amount
        case ticketType = "ticket_type"
    }
}

struct TicketTypeForPurchase: Codable {
    let id: Int
    let typeName: String
    let event: EventForTicket
    
    enum CodingKeys: String, CodingKey {
        case id
        case typeName = "type_name"
        case event
    }
}

struct EventForTicket: Codable {
    let title: String
}

struct TicketPanthi: Codable {
    let title: String
}
