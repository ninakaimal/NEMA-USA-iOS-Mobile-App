//
//  AccountView.swift
//  NEMA USA
//  Created by Arjun on 4/15/25.
//  Updated by Sajith on 4/21/25
//

import SwiftUI

// MARK: – FamilyMember model
struct FamilyMember: Identifiable, Codable {
    let id: Int
    let name: String
    let relationship: String
    let email: String?
    let dob: String?
    let phone: String?
}

struct AccountView: View {
    @AppStorage("authToken") private var authToken: String?
    @State private var profile:      UserProfile?
    @State private var family:       [FamilyMember] = []
    @State private var isLoadingFam: Bool           = false

    var body: some View {
        NavigationView {
            content
        }
//        .navigationBarHidden(false)
        //  .navigationTitle("My Account")
        .navigationBarTitle("My Account", displayMode: .inline)
        .accentColor(.primary)
        .onAppear { loadAllData() }
        .onChange(of: authToken) { _ in loadAllData() }
    }

    @ViewBuilder
    private var content: some View {
        if authToken == nil || profile == nil {
            LoginView()
        } else {
            profileScroll
        }
    }

    /// Scrollable profile + family, with top orange band
    private var profileScroll: some View {
        ZStack(alignment: .top) {
            // orange background behind the nav‑bar
            Color.orange
                .ignoresSafeArea(edges: .top)
                .frame(height: 56)

            // main white content
            Color(.systemBackground)
               // .ignoresSafeArea(edges: .bottom)
                .ignoresSafeArea(edges: [.bottom, .horizontal])

            ScrollView {
                VStack(spacing: 24) {
                    profileCard
                    familySection
                    Spacer(minLength: 32)
                }
                .padding(.vertical)
            }
        }
    }

    /// Main profile card
    private var profileCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 72, height: 72)
                    .overlay(
                        Text(String(profile!.name.prefix(1)))
                            .font(.largeTitle)
                            .foregroundColor(.white)
                    )
                Text(profile!.name)
                    .font(.title)
                    .fontWeight(.semibold)
                Spacer()
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                InfoRow(label: "Email",   value: profile!.email)
                InfoRow(label: "Phone",   value: profile!.phone)
                InfoRow(label: "DOB",     value: profile!.dateOfBirth ?? "Not set")
                InfoRow(label: "Address", value: profile!.address)
                if let notes = profile!.comments {
                    InfoRow(label: "Notes", value: notes, isItalic: true)
                }
                InfoRow(
                    label: "Membership Expires",
                    value: profile!.membershipExpiryDate ?? "Not set"
                )
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
        .shadow(radius: 5, y: 3)
        .padding(.horizontal)
    }

    /// “Your Family” list
    private var familySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your Family")
                .font(.headline)
                .padding(.horizontal)

            if isLoadingFam {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .orange))
                    .padding()
            } else {
                ForEach(family) { member in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(member.name)
                                .font(.subheadline)
                                .fontWeight(.bold)
                            Spacer()
                        }
                        InfoRow(label: "Relation", value: member.relationship)
                        InfoRow(label: "Email",    value: member.email ?? "—")
                        InfoRow(label: "DOB",      value: member.dob   ?? "—")
                        InfoRow(label: "Phone",    value: member.phone ?? "—")
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)
                    .shadow(radius: 3, y: 2)
                    .padding(.horizontal)
                }
            }
        }
    }

    // MARK: – Data Loading

    private func loadAllData() {
        loadLocalProfile()
        loadFamily()
    }

    private func loadLocalProfile() {
        if let cached = DatabaseManager.shared.currentUser {
            profile = cached
        }
        guard let token = authToken else { return }
        NetworkManager.shared.fetchProfile(token: token) { result in
            switch result {
            case .success(let fresh):
                DatabaseManager.shared.saveUser(fresh)
                profile = fresh
            case .failure(let err):
                print("⚠️ Failed to fetch profile:", err)
            }
        }
    }

    private func loadFamily() {
        family = []
        guard let token = authToken,
              let url = URL(string: "https://nema-api.kanakaagro.in/api/family")
        else { return }

        isLoadingFam = true
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: req) { data, _, _ in
            DispatchQueue.main.async { isLoadingFam = false }
            if let data = data,
               let fetched = try? JSONDecoder().decode([FamilyMember].self, from: data) {
                DispatchQueue.main.async { family = fetched }
            }
        }
        .resume()
    }
}

// MARK: – Reusable InfoRow
private struct InfoRow: View {
    let label   : String
    let value   : String
    var isItalic: Bool = false

    var body: some View {
        HStack {
            Text("\(label):")
                .fontWeight(.medium)
            Spacer()
            Text(value)
                .italic(isItalic)
        }
        .font(.subheadline)
        .foregroundColor(.primary)
    }
}

private extension Text {
    func italic(_ flag: Bool) -> Text {
        flag ? self.italic() : self
    }
}
