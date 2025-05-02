//
//  AccountView.swift
//  NEMA USA
//  Created by Arjun on 4/15/25.
//  Updated by Sajith on 4/23/25
//

import SwiftUI

struct AccountView: View {
    @AppStorage("authToken") private var authToken: String?
    @State private var profile: UserProfile?
    @State private var family: [FamilyMember] = []
    @State private var isEditingProfile = false
    @State private var isEditingFamily = false
    @State private var editName = ""
    @State private var editPhone = ""
    @State private var editDOB = ""
    @State private var editAddress = ""
    @State private var isUpdating = false
    @State private var showErrorAlert = false
    @State private var updateErrorMessage = ""
    @State private var isLoadingFam: Bool = false
    @State private var showLogoutConfirmation = false

    var body: some View {
        NavigationView {
            content
                .alert("Update Failed", isPresented: $showErrorAlert) {
                  Button("OK", role: .cancel) {}
                } message: {
                  Text(updateErrorMessage)
                }
                .navigationBarTitle("My Account", displayMode: .inline)
                .navigationBarItems(
                  trailing: HStack {
                    if authToken != nil {
                      if isEditingProfile {
                        Button("Save") { saveProfile() }
                          .foregroundColor(.white)
                          .disabled(isUpdating)
                        Button("Cancel") { isEditingProfile = false }
                          .foregroundColor(.white)
                      } else {
                        Button("Edit") { isEditingProfile = true }
                          .foregroundColor(.white)
                        Button("Logout") { showLogoutConfirmation = true }
                          .foregroundColor(.white)
                      }
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
        .onChange(of: profile) { newProfile in
          guard let p = newProfile else { return }
          editName    = p.name
          editPhone   = p.phone
          editDOB     = p.dateOfBirth ?? ""
          editAddress = p.address
        }
    }

    @ViewBuilder
    private var content: some View {
      if authToken == nil || profile == nil {
        VStack(spacing: 16) {
          LoginView()
          Divider().padding(.horizontal)
          NavigationLink(destination: RegistrationView()) {
            Text("Don’t have an account? Sign Up")
              .font(.subheadline)
              .foregroundColor(.orange)
          }
          .padding(.top, 8)
        }
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
                if isEditingProfile {
                  TextField("Name", text: $editName)
                    .font(.title)
                } else {
                  Text(profile!.name)
                    .font(.title)
                    .fontWeight(.semibold)
                }
                Spacer()
            }
            Divider()

            VStack(alignment: .leading, spacing: 8) {
                InfoRow(label: "Email", value: profile!.email)

                if isEditingProfile {
                  Text("Phone:")
                    .font(.subheadline).fontWeight(.bold)
                  TextField("Phone", text: $editPhone)
                    .keyboardType(.phonePad)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                } else {
                  InfoRow(label: "Phone", value: profile!.phone)
                }

                if isEditingProfile {
                  Text("DOB:")
                    .font(.subheadline).fontWeight(.bold)
                  TextField("YYYY-MM", text: $editDOB)
                    .placeholder(when: editDOB.isEmpty) {
                      Text("YYYY-MM").foregroundColor(.gray)
                    }
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                } else {
                  InfoRow(
                    label: "DOB",
                    value: profile!.dateOfBirth.map(formatDate) ?? "Not set"
                  )
                }

                if isEditingProfile {
                  Text("Address:")
                    .font(.subheadline).fontWeight(.bold)
                  TextField("Address", text: $editAddress)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                } else {
                  InfoRow(label: "Address", value: profile!.address)
                }

                InfoRow(
                  label: "Membership Expires",
                  value: profile!.membershipExpiryDate.map(formatDate) ?? "No info"
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
        HStack {
          Text("Your Family")
            .font(.headline)
          Spacer()
          if authToken != nil {
            if isEditingFamily {
              Button("Save") { saveFamily() }
                .foregroundColor(.orange)
                .disabled(isUpdating)
              Button("Cancel") { isEditingFamily = false }
                .foregroundColor(.orange)
            } else {
              Button("Edit") { isEditingFamily = true }
                .foregroundColor(.orange)
            }
          }
        }
        .padding(.horizontal)

        if isLoadingFam {
          ProgressView()
            .progressViewStyle(CircularProgressViewStyle(tint: .orange))
            .padding()
        } else {
          ForEach(family.indices, id: \.self) { idx in
            let member = family[idx]
            VStack(alignment: .leading, spacing: 8) {
              // Name
              if isEditingFamily {
                Text("Name:")
                  .font(.subheadline).fontWeight(.bold)
                TextField("Name", text: $family[idx].name)
                  .textFieldStyle(RoundedBorderTextFieldStyle())
              } else {
                Text(member.name)
                  .font(.subheadline).fontWeight(.bold)
              }

              // Relation
              if isEditingFamily {
                Text("Relation:")
                  .font(.subheadline).fontWeight(.bold)
                TextField("Relation", text: $family[idx].relationship)
                  .textFieldStyle(RoundedBorderTextFieldStyle())
              } else {
                InfoRow(label: "Relation", value: member.relationship)
              }

              // Email
              if isEditingFamily {
                Text("Email:")
                  .font(.subheadline).fontWeight(.bold)
                TextField("Email", text: Binding(
                  get: { family[idx].email ?? "" },
                  set: { family[idx].email = $0 }
                ))
                .keyboardType(.emailAddress)
                .textFieldStyle(RoundedBorderTextFieldStyle())
              } else {
                InfoRow(label: "Email", value: member.email ?? "—")
              }

              // DOB
              if isEditingFamily {
                Text("DOB:")
                  .font(.subheadline).fontWeight(.bold)
                TextField("YYYY-MM-DD", text: Binding(
                  get: { family[idx].dob ?? "" },
                  set: { family[idx].dob = $0 }
                ))
                .placeholder(when: (family[idx].dob ?? "").isEmpty) {
                  Text("YYYY-MM-DD").foregroundColor(.gray)
                }
                .textFieldStyle(RoundedBorderTextFieldStyle())
              } else {
                InfoRow(label: "DOB", value: member.dob.map(formatDate) ?? "—")
              }

              // Phone
              if isEditingFamily {
                Text("Phone:")
                  .font(.subheadline).fontWeight(.bold)
                TextField("Phone", text: Binding(
                  get: { family[idx].phone ?? "" },
                  set: { family[idx].phone = $0 }
                ))
                .keyboardType(.phonePad)
                .textFieldStyle(RoundedBorderTextFieldStyle())
              } else {
                InfoRow(label: "Phone", value: member.phone ?? "—")
              }
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

    // MARK: – Actions

    private func saveProfile() {
        isUpdating = true
        NetworkManager.shared.updateProfile(
            name: editName,
            phone: editPhone,
            dateOfBirth: editDOB,
            address: editAddress
        ) { result in
            DispatchQueue.main.async {
                isUpdating = false
                switch result {
                case .success(let updated):
                    DatabaseManager.shared.saveUser(updated)
                    profile = updated
                    isEditingProfile = false
                case .failure(let err):
                    updateErrorMessage = err.localizedDescription
                    showErrorAlert = true
                }
            }
        }
    }

    private func saveFamily() {
        guard let token = DatabaseManager.shared.authToken else {
            updateErrorMessage = "Not logged in"
            showErrorAlert = true
            return
        }
        isUpdating = true

        // 1) Build request
        let url = URL(string: "https://nema-api.kanakaagro.in/api/family")!
        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        // 2) JSON-encode your edited family array
        let payload = ["family": family.map { member in
            [
                "id":           member.id,
                "name":         member.name,
                "relationship": member.relationship,
                "email":        member.email ?? "",
                "dob":          member.dob ?? "",
                "phone":        member.phone ?? ""
            ]
        }]

        req.httpBody = try? JSONSerialization.data(withJSONObject: payload, options: [])

        // 3) Fire it off
        URLSession.shared.dataTask(with: req) { data, resp, err in
            DispatchQueue.main.async { self.isUpdating = false }

            if let err = err {
                DispatchQueue.main.async {
                    self.updateErrorMessage = err.localizedDescription
                    self.showErrorAlert = true
                }
                return
            }
            guard let http = resp as? HTTPURLResponse else {
                DispatchQueue.main.async {
                    self.updateErrorMessage = "Invalid server response."
                    self.showErrorAlert = true
                }
                return
            }
            guard (200..<300).contains(http.statusCode) else {
                DispatchQueue.main.async {
                    self.updateErrorMessage = "Server error \(http.statusCode)."
                    self.showErrorAlert = true
                }
                return
            }

            // success! toggle out of edit mode
            DispatchQueue.main.async {
                self.isEditingFamily = false
            }
        }
        .resume()
    }

    // MARK: – Date formatting helpers

    private func formatDate(_ isoString: String) -> String {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = isoFormatter.date(from: isoString) {
            return longStyle(d)
        }
        let isoNoFrac = ISO8601DateFormatter()
        isoNoFrac.formatOptions = [.withInternetDateTime]
        if let d = isoNoFrac.date(from: isoString) {
            return longStyle(d)
        }
        let dfDay = DateFormatter()
        dfDay.dateFormat = "yyyy-MM-dd"
        if let d = dfDay.date(from: isoString) {
            return longStyle(d)
        }
        if isoString.count == 7, isoString.dropFirst(4).first == "-" {
            let dfMonth = DateFormatter()
            dfMonth.dateFormat = "yyyy-MM"
            if let d = dfMonth.date(from: isoString) {
                let out = DateFormatter()
                out.dateFormat = "MMMM yyyy"
                return out.string(from: d)
            }
        }
        return isoString
    }

    private func longStyle(_ date: Date) -> String {
        let out = DateFormatter()
        out.dateStyle = .long
        out.timeStyle = .none
        return out.string(from: date)
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
        guard authToken != nil else { return }
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

