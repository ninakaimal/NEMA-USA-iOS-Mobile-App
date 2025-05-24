//
//  AccountView.swift
//  NEMA USA
//  Created by Arjun on 4/15/25.
//  Updated by Sajith on 4/23/25
//  Updated by Arjun on 5/05/25 to switch to nemausa.org

import SwiftUI

struct AccountView: View {
    @AppStorage("laravelSessionToken") private var authToken: String?
    @AppStorage("membershipExpiryDate") private var cachedExpiryRaw: String?
    @AppStorage("userId") private var userId: Int = 0
    @State private var profile: UserProfile?
    @State private var family: [FamilyMember] = []
    @State private var isEditingProfile = false
    @State private var isEditingFamily  = false
    @State private var editName        = ""
    @State private var editPhone       = ""
    // @State private var editDOB         = ""
    @State private var editAddress     = ""
    @State private var isUpdating      = false
    @State private var showErrorAlert  = false
    @State private var updateErrorMessage = ""
    @State private var isLoadingFamily = false
    @State private var showLogoutConfirmation = false
    
    @State private var membershipId: Int?
    @State private var membershipOptions: [MobileMembershipPackage] = []
    @State private var selectedPackageIndex = 2 // default to 5 years
    @State private var showingRenewSheet     = false
    @State private var approvalURL: URL?      = nil
    @State private var showPaymentError      = false
    @State private var paymentErrorMessage   = ""
    @State private var showPurchaseSuccess   = false
    
    var body: some View {
        NavigationView {
            contentView
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
                            performLogout()
                        },
                        secondaryButton: .cancel()
                    )
                }
        }
        .sheet(item: $approvalURL, onDismiss: {
            approvalURL = nil
        }) { url in
            PayPalView( // Ensure PayPalView is correctly defined elsewhere
                approvalURL: url,
                showPaymentError: $showPaymentError,
                paymentErrorMessage: $paymentErrorMessage,
                showPurchaseSuccess: $showPurchaseSuccess,
                comments: "Membership Payment", // General comment
                successMessage: "Your membership transaction is complete."
            )
        }
        .alert(
            "Payment Successful!",
            isPresented: $showPurchaseSuccess
        ) {
            Button("OK", role: .cancel, action: handlePaymentSuccess)
        }
        .onAppear {
            self.loadAllData()
        }
        .onChange(of: profile) { newProfileValue in
            if let p = newProfileValue {
                setDataForEditing(profile: p)
                self.userId = p.id // Keep @AppStorage userId in sync
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .didReceiveJWT)) { _ in
            self.loadAllData() // Refresh all data on receiving JWT (after login)
        }
           // MARK: – Handle session expiration
        .onReceive(NotificationCenter.default.publisher(for: .didSessionExpire)) { _ in
            authToken = nil // Triggers LoginView via contentView
        }
    }

    
    @ViewBuilder
    private var contentView: some View {
        if authToken == nil {
            LoginView()
        } else if profile == nil && !isUpdating {
            ProgressView("Loading Account…")
                .onAppear {
                    if profile == nil { loadAllData() } // Attempt to load if still nil
                }
        } else if let currentProfile = profile {
            profileScroll(profileData: currentProfile)
        } else {
            ProgressView("Loading Profile...") // Fallback for initial state with token but no profile yet
        }
    }
    
    private var toolbarButtons: some View {
        HStack {
            if authToken != nil {
                if isEditingProfile || isEditingFamily {
                    Button("Save") {
                        if isEditingProfile { saveProfile() }
                        if isEditingFamily { saveFamily() }
                    }
                    .disabled(isUpdating)
                    Button("Cancel") {
                        isEditingProfile = false
                        isEditingFamily = false
                        if let p = profile { setDataForEditing(profile: p) } // Reset edit fields
                        loadFamily() // Revert family edits by reloading
                    }
                } else {
                    Button("Edit Profile") {
                        if let p = profile { setDataForEditing(profile: p) }
                        isEditingProfile = true
                        isEditingFamily = false
                    }
                    Button("Logout") { showLogoutConfirmation = true }
                }
            }
        }
        .foregroundColor(.white) // Note: .navigationBarItems might need .tint(.white) on NavigationView in some iOS versions
    }
    
    private func profileScroll(profileData: UserProfile) -> some View {
        ZStack(alignment: .top) {
            Color.orange.ignoresSafeArea(edges: .top).frame(height: 56)
            Color(.systemBackground).ignoresSafeArea(edges: [.bottom, .horizontal])
            ScrollView {
                VStack(spacing: 24) {
                    profileCard(profileData: profileData)
                    familySection
                    Spacer(minLength: 32)
                }
                .padding(.vertical)
            }
        }
    }
    
    private func profileCard(profileData: UserProfile) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 72, height: 72)
                    .overlay(Text(String(profileData.name.prefix(1))).font(.largeTitle).foregroundColor(.white))
                if isEditingProfile {
                    TextField("Name", text: $editName).font(.title)
                } else {
                    Text(profileData.name).font(.title).fontWeight(.semibold)
                }
                Spacer()
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                InfoRow(label: "Email", value: profileData.email)
                if isEditingProfile {
                    Text("Phone:").font(.subheadline).fontWeight(.bold)
                    TextField("Phone", text: $editPhone).keyboardType(.phonePad).textFieldStyle(RoundedBorderTextFieldStyle())
                } else {
                    InfoRow(label: "Phone", value: profileData.phone)
                }
                if isEditingProfile {
                    Text("Address:").font(.subheadline).fontWeight(.bold)
                    TextField("Address", text: $editAddress).textFieldStyle(RoundedBorderTextFieldStyle())
                } else {
                    InfoRow(label: "Address", value: profileData.address)
                }
                if !isEditingProfile {
                    InfoRow(
                        label: "Membership Expires",
                        value: profileData.isMember ? (profileData.membershipExpiryDate.map(formatDate) ?? "Active") : "Not a member"
                    )
                }
                
                if profileData.isMember, let expiryRaw = profileData.membershipExpiryDate {
                    Text("Your membership is active until \(formatDate(expiryRaw)).")
                        .font(.footnote).foregroundColor(.green)
                } else {
                    Text("Become a NEMA member or renew to enjoy benefits!")
                        .font(.subheadline).foregroundColor(.orange)
                }

                if !membershipOptions.isEmpty {
                    Picker("Membership Package", selection: $selectedPackageIndex) {
                        ForEach(membershipOptions.indices, id: \.self) { idx in
                            if idx < membershipOptions.count {
                                let pkg = membershipOptions[idx]
                                Text("\(pkg.years_of_validity)-year: $\(Int(pkg.amount))").tag(idx) // Simplified text
                            }
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle()).padding(.vertical, 8)
                    
                    HStack {
                        Spacer()
                        Button(action: { // Moved action to be the first argument or clearly labeled
                            guard selectedPackageIndex < membershipOptions.count else {
                                paymentErrorMessage = "Please select a valid membership package."
                                showPaymentError = true; return
                            }
                            let pkg = membershipOptions[selectedPackageIndex]
                            let itemTitle = "NEMA Membership – \(pkg.years_of_validity)-year"
                            let currentMembershipType = profileData.isMember ? "renew" : "membership"
                            
                            print("MEMBER_ACTION_TRACE: Type: \(currentMembershipType), Profile ID: \(profileData.id), Pkg ID: \(pkg.id)")

                            PaymentManager.shared.createOrder(
                                amount: "\(Int(pkg.amount))",
                                eventTitle: itemTitle,
                                eventID: nil,
                                email: profileData.email,
                                name: profileData.name,
                                phone: profileData.phone,
                                membershipType: currentMembershipType,
                                packageId: pkg.id,
                                packageYears: pkg.years_of_validity,
                                userId: profileData.id,
                                panthiId: nil,
                                completion: { result in
                                    switch result {
                                    case .success(let url): approvalURL = url
                                    case .failure(let err): handlePaymentManagerError(err, context: "membership payment")
                                    }
                                }
                            )
                        }) { // Explicitly provide the label view
                            Text(profileData.isMember ? "Renew Membership" : "Become a Member") // <-- WRAP STRING IN TEXT()
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.orange)
                        Spacer()
                    }
                } else {
                    ProgressView("Loading membership options...").padding(.vertical)
                }
            }
            .padding()
            .background(Color(.secondarySystemBackground)).cornerRadius(16)
            .shadow(color: Color.black.opacity(0.05), radius: 3, x: 0, y: 3)
            .padding(.horizontal)
        }
    }
    private var familySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Your Family").font(.headline)
                Spacer()
                if authToken != nil {
                    if isEditingFamily {
                        Button("Save", action: saveFamily).foregroundColor(.orange).disabled(isUpdating)
                        Button("Cancel") {
                            isEditingFamily = false
                            loadFamily() // Reload to discard edits
                        }.foregroundColor(.orange)
                    } else {
                        Button("Edit") {
                            isEditingFamily = true
                            isEditingProfile = false // Only one edit mode
                        }.foregroundColor(.orange)
                    }
                }
            }
            .padding(.horizontal)
            
            if isLoadingFamily {
                ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .orange)).padding()
            } else if family.isEmpty {
                Text("No family members added yet. Tap 'Edit' to add.").font(.subheadline).foregroundColor(.gray)
                    .padding().frame(maxWidth: .infinity, alignment: .center)
            } else {
                ForEach($family) { $member in // Use binding here
                    VStack(alignment: .leading, spacing: 8) {
                        EditableInfoRow(label: "Name", text: $member.name, isEditing: isEditingFamily)
                        EditableInfoRow(label: "Relation", text: $member.relationship, isEditing: isEditingFamily)
                        EditableInfoRow(label: "Email", text: Binding( // Custom binding for optional String
                            get: { member.email ?? "" }, set: { member.email = $0.isEmpty ? nil : $0 }
                        ), isEditing: isEditingFamily, keyboardType: .emailAddress)
                        
                        EditableInfoRow(
                            label: "DOB",
                            text: Binding(
                            get: { member.dob ?? "" },
                            set: { member.dob = $0.isEmpty ? nil : $0 }
                        ),
                            isEditing: isEditingFamily,
                            placeholder: "YYYY-MM-DD"
                            )
                        EditableInfoRow(label: "Phone", text: Binding(
                            get: { member.phone ?? "" }, set: { member.phone = $0.isEmpty ? nil : $0 }
                        ), isEditing: isEditingFamily, keyboardType: .phonePad)
                    }
                    .padding().background(Color(.secondarySystemBackground)).cornerRadius(12)
                    .shadow(color: Color.black.opacity(0.05), radius: 3, y: 2).padding(.horizontal)
                }
            }
        }
    }

        // MARK: – Actions
    
    private func performLogout() {
        DatabaseManager.shared.clearSession()
        authToken = nil; profile = nil; family = []; cachedExpiryRaw = nil; userId = 0
    }

    private func setDataForEditing(profile: UserProfile) {
        editName = profile.name
        editPhone = profile.phone
        editAddress = profile.address
    }
        
    private func saveProfile() {
        isUpdating = true
        NetworkManager.shared.updateProfile(name: editName, phone: editPhone, address: editAddress) { result in
            DispatchQueue.main.async {
                isUpdating = false
                switch result {
                case .success(let updatedProfile):
                    DatabaseManager.shared.saveUser(updatedProfile)
                    self.profile = updatedProfile
                    self.cachedExpiryRaw = updatedProfile.membershipExpiryDate
                    isEditingProfile = false
                    self.loadMembership()
                case .failure(let err): handlePaymentManagerError(err, context: "profile update")
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
                    DatabaseManager.shared.saveFamily(family) // Cache the locally edited version
                    // Optionally call loadFamily() here to re-fetch from server and confirm.
                case .failure(let err): handlePaymentManagerError(err, context: "family update")
                }
            }
        }
    }
        
        // MARK: – Date formatting helpers
        
    private func formatDate(_ dateString: String) -> String {
        // Using Event's static formatters if they are accessible and cover necessary formats
        if let date = Event.iso8601DateTimeFormatter.date(from: dateString) { return longStyle(date) }
//        if let date = Event.iso8601DateOnlyFormatter.date(from: dateString) { return longStyle(date) } // For "yyyy-MM-dd"
        // Fallback for "yyyy-MM"
        if dateString.count == 7 && dateString.contains("-") {
             let monthFormatter = DateFormatter()
             monthFormatter.dateFormat = "yyyy-MM"
             monthFormatter.locale = Locale(identifier: "en_US_POSIX")
             if let date = monthFormatter.date(from: dateString) {
                 let out = DateFormatter()
                 out.dateFormat = "MMMM yyyy" // e.g., "September 2025"
                 return out.string(from: date)
             }
         }
        return dateString // Fallback
    }
        
    private func longStyle(_ date: Date) -> String {
        let out = DateFormatter(); out.dateStyle = .long; out.timeStyle = .none; return out.string(from: date)
    }
    
    private func handlePaymentSuccess() {
        print("✅ PayPal Payment Confirmed by App. Reloading all data to reflect membership changes.")
        loadAllData() // This will re-fetch profile and membership details.
    }
        
    private func handlePaymentManagerError(_ error: Error, context: String = "operation") {
        if let paymentErr = error as? PaymentError { // Assuming PaymentError is your custom enum
            switch paymentErr {
            case .serverError(let msg): updateErrorMessage = "Server Error (\(context)): \(msg)"
            case .invalidResponse: updateErrorMessage = "Invalid Response (\(context))."
            case .parseError(let msg): updateErrorMessage = "Parse Error (\(context)): \(msg)"
            }
        } else {
            updateErrorMessage = "Error during \(context): \(error.localizedDescription)"
        }
        showErrorAlert = true
    }
        
        // MARK: – Data Loading
        
    private func loadAllData() {
        print("🔄 [AccountView] loadAllData called.")
        loadLocalProfile()
        loadRemoteProfile() // This will also trigger loadMembership after profile fetch
        loadFamily()
        fetchPackages()
    }
    
    private func fetchPackages() {
        NetworkManager.shared.fetchMembershipPackages { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let packs):
                    self.membershipOptions = packs
                    if self.selectedPackageIndex >= packs.count && !packs.isEmpty { self.selectedPackageIndex = 0 }
                    else if packs.isEmpty { self.selectedPackageIndex = 0 }
                case .failure(let err):
                    print("⚠️ Failed to load membership packages: \(err.localizedDescription)")
                    // self.updateErrorMessage = "Could not load membership options."; self.showErrorAlert = true;
                }
            }
        }
    }
    
    private func loadMembership() {
        // Use self.profile if available and has a valid ID, otherwise try DatabaseManager.shared.currentUser
        guard let effectiveProfile = self.profile ?? DatabaseManager.shared.currentUser, effectiveProfile.id != 0 else {
            print("ℹ️ [AccountView] loadMembership: No user profile ID (or ID is 0), cannot fetch membership.")
            // If no profile ID, ensure UI reflects "Not a member" state by clearing cachedExpiryRaw
            self.cachedExpiryRaw = nil
            if var p = self.profile { p.membershipExpiryDate = nil; self.profile = p; }
            return
        }
        
        NetworkManager.shared.fetchMembership { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let membership):
                    print("✅ [AccountView] Fetched membership. DB Expiry: \(membership.exp_date), ID: \(membership.id)")
                    self.cachedExpiryRaw = membership.exp_date
                    self.membershipId = membership.id // <-- Make sure membershipId is set

                    if var p = self.profile, p.id == membership.user_id { // Ensure we're updating the correct profile
                        p.membershipExpiryDate = membership.exp_date
                        self.profile = p // This updates the @State
                        DatabaseManager.shared.saveUser(p) // Save updated profile to cache
                    } else if var cachedUser = DatabaseManager.shared.currentUser, cachedUser.id == membership.user_id {
                         // This case handles if self.profile wasn't set yet from a fresh remote fetch
                        cachedUser.membershipExpiryDate = membership.exp_date
                        DatabaseManager.shared.saveUser(cachedUser)
                        self.profile = cachedUser
                    }

                case .failure(let err):
                    print("⚠️ [AccountView] Failed to fetch membership details: \(err.localizedDescription)")
                    // On failure, it might mean no active membership or an error.
                    // Clearing local expiry might be appropriate if the error indicates "not found."
                    // For now, retaining the cached one on general error. If error is 404 Not Found, then clear.
                    if case NetworkError.invalidResponse = err { // Example: 404 from backend
                        self.cachedExpiryRaw = nil
                        if var p = self.profile { p.membershipExpiryDate = nil; self.profile = p; DatabaseManager.shared.saveUser(p); }
                    }
                }
            }
        }
    }
    
    private func loadLocalProfile() {
        if let cached = DatabaseManager.shared.currentUser {
            self.profile = cached
            self.userId = cached.id // Sync @AppStorage userId
            print("ℹ️ [AccountView] Loaded profile from cache: \(cached.name), ID: \(cached.id)")
        }
    }

    private func loadRemoteProfile() {
        // Use JWT token for fetching profile, not laravelSessionToken for API calls
        guard DatabaseManager.shared.jwtApiToken != nil else {
            print("ℹ️ [AccountView] No JWT token, cannot fetch remote profile.")
            if authToken != nil { // If laravel token exists but JWT doesn't, might indicate incomplete login
                authToken = nil // Force re-login via LoginView
            }
            return
        }
        
        NetworkManager.shared.fetchProfileJSON { result in // Assumes fetchProfileJSON uses JWT
            DispatchQueue.main.async {
                switch result {
                case .success(let freshProfile):
                    DatabaseManager.shared.saveUser(freshProfile)
                    self.profile = freshProfile
                    self.cachedExpiryRaw = freshProfile.membershipExpiryDate
                    self.userId = freshProfile.id
                    print("✅ [AccountView] Fetched and updated remote profile: \(freshProfile.name), ID: \(freshProfile.id)")
                    self.loadMembership() // Refresh membership status after profile is updated
                case .failure(let err):
                    print("⚠️ [AccountView] Failed to fetch remote profile: \(err.localizedDescription)")
                    if case NetworkError.invalidResponse = err { // e.g. 401 Unauthorized
                        print("‼️ Session might have expired. Clearing auth token.")
                        self.authToken = nil // Trigger re-login
                    }
                }
            }
        }
    }
        
    private func loadFamily() {
        if let cached = DatabaseManager.shared.currentFamily { family = cached }
        guard DatabaseManager.shared.jwtApiToken != nil else { return } // Check JWT for API calls
        isLoadingFamily = true
        NetworkManager.shared.fetchFamily { result in // Assumes fetchFamily uses appropriate auth (JWT or Laravel session)
            DispatchQueue.main.async {
                self.isLoadingFamily = false
                switch result {
                case .success(let fam): self.family = fam; DatabaseManager.shared.saveFamily(fam)
                case .failure(let err): print("⚠️ [AccountView] Failed to fetch family: \(err.localizedDescription)")
                }
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
private struct EditableInfoRow: View {
    let label: String
    @Binding var text: String
    let isEditing: Bool
    var placeholder: String = "" // Default placeholder if none provided
    var keyboardType: UIKeyboardType = .default

    var body: some View {
        VStack(alignment: .leading, spacing: 2) { // Reduced spacing for a tighter look
            Text("\(label):")
                .font(.caption) // Using .caption for the label to make it smaller
                .foregroundColor(.gray)
            if isEditing {
                TextField(placeholder.isEmpty ? label : placeholder, text: $text) // Use label as placeholder if specific one isn't set
                    .textFieldStyle(PlainTextFieldStyle()) // A simpler style for inline editing
                    .keyboardType(keyboardType)
                    .padding(.vertical, 4) // Give a little vertical space for tapping
                Divider() // Visual separator for the text field in edit mode
            } else {
                Text(text.isEmpty && placeholder.isEmpty ? "—" : (text.isEmpty ? (placeholder.isEmpty ? "—" : placeholder) : text) ) // Show dash if text is empty and no placeholder
                    .font(.subheadline)
                    .foregroundColor(text.isEmpty && !placeholder.isEmpty ? .gray.opacity(0.7) : .primary) // Dim placeholder text
                    .padding(.vertical, 4) // Match padding
            }
        }
    }
}
