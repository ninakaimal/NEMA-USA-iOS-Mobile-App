//
//  MasterDataModel.swift
//  NEMA USA
//  Created by Arjun on 4/15/25.
//  Updated by Sajith on 4/21/25
//

import Foundation

struct UserProfile: Codable, Equatable {
    let id: Int
    let name: String
    let dateOfBirth: String?   // matches JSON "dateOfBirth"
    let address: String
    let email: String
    let phone: String
    let comments: String?
    var membershipExpiryDate: String?
    
    enum CodingKeys: String, CodingKey {
            case id
            case name
            case dateOfBirth
            case address
            case email
            case phone
            case comments
            case membershipExpiryDate = "membership_expiry_date"
        }
}

struct FamilyMember: Identifiable, Codable {
    let id: Int
    var name: String
    var relationship: String
    var email: String?
    var dob: String?
    var phone: String?
}
