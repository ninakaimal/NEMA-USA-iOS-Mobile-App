//
//  EventProgram.swift
//  NEMA USA
//
//  Created by Nina on 6/1/25.
//

import Foundation

struct EventProgram: Identifiable, Decodable, Hashable {
    let id: String
    let name: String
    let time: String?
    let rulesAndGuidelines: String?
    let registrationStatus: String?
    let categories: [ProgramCategory]
    
    enum CodingKeys: String, CodingKey {
        case id, name, time, categories
        case rulesAndGuidelines = "rules_and_guidelines"
        case registrationStatus = "registration_status"
    }
}

struct ProgramCategory: Identifiable, Decodable, Hashable {
    let id: Int
    let name: String
}
