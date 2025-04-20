//
//  UserProfile.swift
//  NEMA USA
//
//  Created by Arjun on 4/15/25.
//
import Foundation

struct UserProfile: Codable {
    let id: Int
    let name: String
    let dob: String?
    let address: String
    let email: String
    let phone: String
    let comments: String?
}

