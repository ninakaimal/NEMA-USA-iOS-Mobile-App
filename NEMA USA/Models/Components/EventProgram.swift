//
//  EventProgram.swift
//  NEMA USA
//
//  Created by Nina on 6/1/25.
//  Added Practice Locations feature on 7/8/2025

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
    
    enum CodingKeys: String, CodingKey {
        case id, name, time, categories, event
        case rulesAndGuidelines = "rules_and_guidelines"
        case registrationStatus = "registration_status"
        case practiceLocations = "practice_locations"
    }
}

struct ProgramCategory: Identifiable, Codable, Hashable {
    let id: Int
    let name: String
}
