//
//  Participant.swift
//  NEMA USA
//
//  Created by Sajith on 6/18/25.
//

import Foundation

// Model for Program Registration details
struct Participant: Codable, Identifiable {
    let id: Int
    let comments: String?
    let amount: Double
    let regStatus: String
    let details: [ParticipantDetail]
    let category: ProgramCategoryContainer
    
    enum CodingKeys: String, CodingKey {
        case id, comments, amount, details, category
        case regStatus = "reg_status"
    }
}

struct ParticipantDetail: Codable, Identifiable {
    let id: Int
    let name: String
    let age: Int?
}

// Nested containers to match the backend JSON structure
struct ProgramCategoryContainer: Codable {
    let programs: EventProgram
    let age: ProgramAgeCategory
}

struct ProgramAgeCategory: Codable {
    let name: String
}

// NOTE: Your `EventProgram` model is already defined and can be reused here.
