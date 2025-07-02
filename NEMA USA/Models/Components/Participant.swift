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
    let programs: ProgramForParticipant  // Changed from EventProgram to avoid conflicts
    let age: ProgramAgeCategory
}

struct ProgramForParticipant: Codable {
    let name: String
    let event: EventForParticipant
}

struct EventForParticipant: Codable {
    let title: String
}

struct ProgramAgeCategory: Codable {
    let name: String
}
