//
//  AccountView.swift
//  NEMA USA
//  Created by Arjun on 4/15/25.
//  Updated by Sajith on 4/21/25
//

import SwiftUI

struct AccountView: View {
    @AppStorage("authToken") private var authToken: String?
    @State private var profile:      UserProfile?
    @State private var family:       [FamilyMember] = []
    @State private var isLoadingFam: Bool           = false
    @State private var showLogoutConfirmation = false

    var body: some View {
        NavigationView {
            content
                .navigationBarTitle("My Account", displayMode: .inline)
                .navigationBarItems(
                    trailing:
                        // only show Logout if we actually have a token
                        Group {
                            if authToken != nil {
                                Button("Logout") {
                                    showLogoutConfirmation = true
                                }
                                .foregroundColor(.white)
                            }
                        }
                )
                .alert(isPresented: $showLogoutConfirmation) {
                    Alert(
                        title: Text("Logout"),
                        message: Text("Are you sure you want to log out?"),
                        primaryButton: .destructive(Text("Logout")) {
                            DatabaseManager.shared.clearSession()
                            authToken = nil
                        },
                        secondaryButton: .cancel()
                    )
                }
        }
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

    private var profileScroll: some View {
        ZStack(alignment: .top) {
            Color.orange
                .ignoresSafeArea(edges: .top)
                .frame(height: 56)

            Color(.systemBackground)
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
        // Show any cached data immediately
        if let cached = DatabaseManager.shared.currentUser {
            profile = cached
        }
        // Bail out if we don’t have a token yet
        guard authToken != nil else { return }

        // 📡 Fetch fresh profile
        NetworkManager.shared.fetchProfile { result in
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

