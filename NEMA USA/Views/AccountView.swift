//
//  AccountView.swift
//  NEMA USA
//  Created by Arjun on 4/15/25.
//  Updated by Sajith on 4/23/25
//  Updated by Arjun on 5/05/25 to switch to nemausa.org

import SwiftUI

struct AccountView: View {
    @AppStorage("laravelSessionToken") private var authToken: String?
    @State private var profile: UserProfile?
    @State private var family: [FamilyMember] = []
    @State private var isEditingProfile = false
    @State private var isEditingFamily  = false
    @State private var editName        = ""
    @State private var editPhone       = ""
    @State private var editDOB         = ""
    @State private var editAddress     = ""
    @State private var isUpdating      = false
    @State private var showErrorAlert  = false
    @State private var updateErrorMessage = ""
    @State private var isLoadingFamily = false
    @State private var showLogoutConfirmation = false
    

    var body: some View {
        NavigationView {
            content
                .navigationBarTitle("My Account", displayMode: .inline)
                .navigationBarItems(trailing: toolbarButtons)
                .alert("Update Failed", isPresented: $showErrorAlert) {
                    Button("OK", role: .cancel) { }
                } message: {
                    Text(updateErrorMessage)
                }
                .alert(isPresented: $showLogoutConfirmation) {
                    Alert(
                        title: Text("Logout"),
                        message: Text("Are you sure you want to log out?"),
                        primaryButton: .destructive(Text("Logout")) {
                            DatabaseManager.shared.clearSession()
                            authToken = nil
                            profile = nil
                            family = []
                        },
                        secondaryButton: .cancel()
                    )
                }
        }
        .onAppear(perform: loadAllData)
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
        // <-- only show login when NOT authenticated
        if authToken == nil {
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

        // <-- spinner while we fetch/scrape the profile
        } else if profile == nil {
            ProgressView("Loading…")
                .padding()

        // <-- finally show the actual account UI
        } else {
            profileScroll
        }
    }

    private var toolbarButtons: some View {
        HStack {
            if authToken != nil {
                if isEditingProfile {
                    Button("Save", action: saveProfile)
                        .disabled(isUpdating)
                    Button("Cancel") { isEditingProfile = false }
                } else {
                    Button("Edit") { isEditingProfile = true }
                    Button("Logout") { showLogoutConfirmation = true }
                }
            }
        }
        .foregroundColor(.white)
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
                    Text("Phone:").font(.subheadline).fontWeight(.bold)
                    TextField("Phone", text: $editPhone)
                        .keyboardType(.phonePad)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                } else {
                    InfoRow(label: "Phone", value: profile!.phone)
                }
//                if isEditingProfile {
//                    Text("DOB:").font(.subheadline).fontWeight(.bold)
//                    TextField("YYYY-MM-DD", text: $editDOB)
//                        .textFieldStyle(RoundedBorderTextFieldStyle())
//                } else {
//                    InfoRow(label: "DOB", value: profile!.dateOfBirth.map(formatDate) ?? "Not set")
//                }
                if isEditingProfile {
                    Text("Address:").font(.subheadline).fontWeight(.bold)
                    TextField("Address", text: $editAddress)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                } else {
                    InfoRow(label: "Address", value: profile!.address)
                }
//                InfoRow(
//                    label: "Membership Expires",
//                    value: profile!.membershipExpiryDate.map(formatDate) ?? "No info"
//                )
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
                        Button("Save", action: saveFamily)
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

            if isLoadingFamily {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .orange))
                    .padding()
            } else {
                ForEach(family.indices, id: \.self) { idx in
                    let member = family[idx]
                    VStack(alignment: .leading, spacing: 8) {
                        if isEditingFamily {
                            Text("Name:").font(.subheadline).fontWeight(.bold)
                            TextField("Name", text: $family[idx].name)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        } else {
                            Text(member.name)
                                .font(.subheadline)
                                .fontWeight(.bold)
                        }

                        if isEditingFamily {
                            Text("Relation:").font(.subheadline).fontWeight(.bold)
                            TextField("Relation", text: $family[idx].relationship)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        } else {
                            InfoRow(label: "Relation", value: member.relationship)
                        }

                        if isEditingFamily {
                            Text("Email:").font(.subheadline).fontWeight(.bold)
                            TextField("Email", text: Binding(
                                get: { family[idx].email ?? "" },
                                set: { family[idx].email = $0 }
                            ))
                            .keyboardType(.emailAddress)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        } else {
                            InfoRow(label: "Email", value: member.email ?? "—")
                        }

                        if isEditingFamily {
                            Text("DOB:").font(.subheadline).fontWeight(.bold)
                            TextField("YYYY-MM-DD", text: Binding(
                                get: { family[idx].dob ?? "" },
                                set: { family[idx].dob = $0 }
                            ))
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        } else {
                            InfoRow(label: "DOB", value: member.dob.map(formatDate) ?? "—")
                        }

                        if isEditingFamily {
                            Text("Phone:").font(.subheadline).fontWeight(.bold)
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
                    name:    editName,
                    phone:   editPhone,
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
                isUpdating = true
                NetworkManager.shared.updateFamily(family) { result in
                    DispatchQueue.main.async {
                        isUpdating = false
                        switch result {
                        case .success():
                            isEditingFamily = false
                        case .failure(let err):
                            updateErrorMessage = err.localizedDescription
                            showErrorAlert = true
                        }
                    }
                }
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
        loadRemoteProfile()
        loadFamily()
    }

    private func loadLocalProfile() {
        if let cached = DatabaseManager.shared.currentUser {
            profile = cached
        }
    }

    private func loadRemoteProfile() {
        guard authToken != nil else { return }
        NetworkManager.shared.fetchProfile { result in
                        switch result {
                        case .success(let fresh):
                            // if the scrape came back with no email *and* no phone, skip it—
                            // that means our parsing failed and we don’t want to clobber
                            // the user’s real cached data.
                            let hasContact = !fresh.email.isEmpty || !fresh.phone.isEmpty
                            guard hasContact else {
                                print("⚠️ Skipping remote‐profile overwrite: no contact info")
                                return
                            }
                            // otherwise update both cache and UI
                            DatabaseManager.shared.saveUser(fresh)
                            profile = fresh
            
                        case .failure(let err):
                            print("⚠️ Failed to fetch profile:", err)
                        }
        }
    }

    private func loadFamily() {
        if let cached = DatabaseManager.shared.currentFamily {
            family = cached
        }
        guard authToken != nil else { return }
        isLoadingFamily = true
        NetworkManager.shared.fetchFamily { result in
            DispatchQueue.main.async { isLoadingFamily = false }
            switch result {
            case .success(let fam):
                family = fam
                DatabaseManager.shared.saveFamily(fam)   // cache latest
            case .failure(let err):
                print("⚠️ Failed to fetch family:", err)
                // leave `family` as whatever was cached (or empty)
            }
        }
    }
}

// MARK: – Reusable InfoRow

private struct InfoRow: View {
    let label: String
    let value: String
    var body: some View {
        HStack {
            Text("\(label):")
                .fontWeight(.medium)
            Spacer()
            Text(value)
                .font(.subheadline)
        }
    }
}
