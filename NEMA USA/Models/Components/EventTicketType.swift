//
//  EventTicketType.swift
//  NEMA USA
//
//  Created by Sajith on 5/22/25.

import Foundation

struct EventTicketType: Identifiable, Codable, Hashable {
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
    let event: Event?
    
    enum CodingKeys: String, CodingKey {
        case id, event
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
} // end of file
