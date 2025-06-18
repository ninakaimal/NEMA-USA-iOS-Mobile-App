//
//  EventProgram.swift
//  NEMA USA
//
//  Created by Nina on 6/1/25.
//

import Foundation

struct EventProgram: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let time: String?
    let rulesAndGuidelines: String?
    let registrationStatus: String?
    let categories: [ProgramCategory]
    let event: Event?
    
    enum CodingKeys: String, CodingKey {
        case id, name, time, categories, event
        case rulesAndGuidelines = "rules_and_guidelines"
        case registrationStatus = "registration_status"
    }
}

struct ProgramCategory: Identifiable, Codable, Hashable {
    let id: Int
    let name: String
}
