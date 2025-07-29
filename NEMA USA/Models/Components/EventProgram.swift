//
//  EventProgram.swift
//  NEMA USA
//
//  Created by Nina on 6/1/25.
//  Added Practice Locations feature on 7/8/2025
//  Added Pricing fields for PayPal integration on 7/27/2025

import Foundation

struct EventProgram: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let time: String?
    let rulesAndGuidelines: String?
    let registrationStatus: String?
    let categories: [ProgramCategory]
    let practiceLocations: [PracticeLocation]?
    let event: Event?
    
    // PRICING FIELDS
    let othersFee: Double?
    let paidMemberFee: Double?
    let penalty: Double?
    let currencyCode: String?
    
    enum CodingKeys: String, CodingKey {
        case id, name, time, categories, event
        case rulesAndGuidelines = "rules_and_guidelines"
        case registrationStatus = "registration_status"
        case practiceLocations = "practice_locations"
        case othersFee = "others_fee"
        case paidMemberFee = "paid_member_fee"
        case penalty = "penalty"
        case currencyCode = "currency_code"
    }
    
    // COMPUTED PROPERTIES FOR PRICING LOGIC
    var isPaidProgram: Bool {
        return (othersFee ?? 0.0) > 0.0 || (paidMemberFee ?? 0.0) > 0.0
    }
    
    func price(isMember: Bool) -> Double {
        if isMember && (paidMemberFee ?? 0.0) > 0.0 {
            return paidMemberFee ?? 0.0
        }
        return othersFee ?? 0.0
    }
    
    var formattedPrice: String {
        let memberPrice = paidMemberFee ?? 0.0
        let nonMemberPrice = othersFee ?? 0.0
        
        if memberPrice > 0.0 && nonMemberPrice > 0.0 {
            if memberPrice == nonMemberPrice {
                return "$\(String(format: "%.0f", memberPrice))"
            } else {
                return "$\(String(format: "%.0f", memberPrice)) (Members) / $\(String(format: "%.0f", nonMemberPrice)) (Non-Members)"
            }
        } else if memberPrice > 0.0 {
            return "$\(String(format: "%.0f", memberPrice)) (Members Only)"
        } else if nonMemberPrice > 0.0 {
            return "$\(String(format: "%.0f", nonMemberPrice))"
        } else {
            return "Free"
        }
    }
}

struct ProgramCategory: Identifiable, Codable, Hashable {
    let id: Int
    let name: String
}
