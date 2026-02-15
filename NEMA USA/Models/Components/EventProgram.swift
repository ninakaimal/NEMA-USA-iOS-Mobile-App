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
    let rulesDescriptionHTML: String?
    let instructionsHTML: String?
    let refundPolicyHTML: String?
    let penaltyDetails: PenaltyDetails?
    let registrationStatus: String?
    let categories: [ProgramCategory]
    let practiceLocations: [PracticeLocation]?
    let event: Event?
    
    // PRICING FIELDS
    let othersFee: Double?
    let paidMemberFee: Double?
    let penalty: Double?
    let currencyCode: String?
    let regType: Int?
    let minTeamSize: Int?
    let maxTeamSize: Int?
    let showGuruOption: Bool?
    let showGroupNameOption: Bool?
    let showAgeOption: Bool?
    
    enum CodingKeys: String, CodingKey {
        case id, name, time, categories, event
        case rulesAndGuidelines = "rules_and_guidelines"
        case rulesDescriptionHTML = "rules_desc"
        case instructionsHTML = "instructions_html"
        case refundPolicyHTML = "refund_policy_html"
        case penaltyDetails = "penalty_details"
        case registrationStatus = "registration_status"
        case practiceLocations = "practice_locations"
        case othersFee = "others_fee"
        case paidMemberFee = "paid_member_fee"
        case penalty = "penalty"
        case currencyCode = "currency_code"
        case regType = "reg_type"
        case minTeamSize = "min_team_size"
        case maxTeamSize = "max_team_size"
        case showGuruOption = "show_guru_option"
        case showGroupNameOption = "show_group_name_option"
        case showAgeOption = "show_age_option"
    }
    
    var minTeamSizeValue: Int { max(1, minTeamSize ?? 1) }
    var maxTeamSizeValue: Int { max(minTeamSizeValue, maxTeamSize ?? minTeamSizeValue) }
    var isGroupProgram: Bool {
        return maxTeamSizeValue > 1 || minTeamSizeValue > 1 || (regType ?? 0) == 2
    }
    
    // COMPUTED PROPERTIES FOR PRICING LOGIC
    var isPaidProgram: Bool {
        return (othersFee ?? 0.0) > 0.0 || (paidMemberFee ?? 0.0) > 0.0
    }

    var isWaitlistProgram: Bool {
        return registrationStatus == "Join Waitlist"
    }

    // Computed property to Only require payment if it's a paid program AND not waitlist
    var requiresPayment: Bool {
        return isPaidProgram && !isWaitlistProgram
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

struct PenaltyDetails: Codable, Hashable {
    let regCloseDate: String?
    let withdrawalPenaltyText: String?
    let penaltyAmount: Double?
    let penaltyType: String?
    let showPenalty: Bool?

    enum CodingKeys: String, CodingKey {
        case regCloseDate = "reg_close_date"
        case withdrawalPenaltyText = "withdrawal_penalty_text"
        case penaltyAmount = "penalty_amount"
        case penaltyType = "penalty_type"
        case showPenalty = "show_penalty"
    }
}

struct ProgramCategory: Identifiable, Codable, Hashable {
    let id: Int
    let name: String
    let minAge: Int?
    let maxAge: Int?
    
    enum CodingKeys: String, CodingKey {
        case id, name
        case minAge = "min_age"
        case maxAge = "max_age"
    }
}
