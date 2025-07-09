//
//  PracticeLocation.swift
//  NEMA USA
//
//  Created by Nina Kaimal on 7/8/25.
//
import Foundation

struct PracticeLocation: Identifiable, Codable, Hashable {
    let id: Int
    let location: String
    
    enum CodingKeys: String, CodingKey {
        case id, location
    }
}
