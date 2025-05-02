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
    let membershipExpiryDate: String?
}

struct FamilyMember: Identifiable, Codable {
    let id: Int
    var name: String
    var relationship: String
    var email: String?
    var dob: String?
    var phone: String?
}
