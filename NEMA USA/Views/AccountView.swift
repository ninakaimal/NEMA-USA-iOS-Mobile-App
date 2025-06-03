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
    @State private var currentActionIsRenewal: Bool = false // Tracks if the action is renewal or new
    @State private var paymentDataFromPayPal: PaymentConfirmationResponse? // Holds response from PayPalView
    
    // State for membership button processing
    @State private var isProcessingMembershipAction: Bool = false
    
    // Relation list
    private let relationshipOptions = ["spouse", "son", "daughter"]
    
    // Date of Birth properties
    @State private var editMonth = Calendar.current.component(.month, from: Date())
    @State private var editYear = Calendar.current.component(.year, from: Date())
    
    // New state variables for profile editing - Family, DOB
    @State private var editingDOB: [Int: (month: Int, year: Int)] = [:]
    @State private var showDeleteFamilyMemberConfirmation = false
    @State private var familyMemberToDelete: FamilyMember? = nil
    @State private var showingAddMemberSheet = false
    @State private var newMemberName = ""
    @State private var newMemberRelationship = "spouse" // Default or first from your options
    @State private var newMemberEmail: String? = nil
    @State private var newMemberPhone: String? = nil
    @State private var newMemberDOBMonth = Calendar.current.component(.month, from: Date())
    @State private var newMemberDOBYear = Calendar.current.component(.year, from: Date() - 30) // Default to 30 years ago
    
    struct MonthYearPicker: View {
        @Binding var selectedMonth: Int
        @Binding var selectedYear: Int
        
        let months = Calendar.current.monthSymbols
        let years = Array((Calendar.current.component(.year, from: Date()) - 110)...Calendar.current.component(.year, from: Date())).reversed()
        
        var body: some View {
            HStack {
                Picker("Month", selection: $selectedMonth) {
                    ForEach(0..<months.count, id: \.self) { idx in
                        Text(months[idx]).tag(idx + 1)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                
                Picker("Year", selection: $selectedYear) {
                    ForEach(years, id: \.self) { year in
                        Text(String(format: "%d", year)).tag(year)
                    }
                }
                .pickerStyle(MenuPickerStyle())
            }
        }
    }
    
    private struct AddFamilyMemberSheetView: View {
        @Binding var isPresented: Bool
        
        // Use @State for fields within the sheet
        @State var nameState: String
        @State var relationshipState: String
        @State var emailState: String
        @State var phoneState: String
        @State var dobMonthState: Int
        @State var dobYearState: Int
        
        let relationshipOptions: [String]
        var onSave: ( (name: String, relationship: String, email: String?, phone: String?, dob: String) ) -> Void

        // Initializer to receive initial values for the @State properties from AccountView's @State
        init(isPresented: Binding<Bool>,
             name: String, relationship: String, email: String, phone: String,
             dobMonth: Int, dobYear: Int,
             relationshipOptions: [String],
             onSave: @escaping ( (name: String, relationship: String, email: String?, phone: String?, dob: String) ) -> Void) {
            self._isPresented = isPresented
            self._nameState = State(initialValue: name)
            self._relationshipState = State(initialValue: relationship)
            self._emailState = State(initialValue: email)
            self._phoneState = State(initialValue: phone)
            self._dobMonthState = State(initialValue: dobMonth)
            self._dobYearState = State(initialValue: dobYear)
            self.relationshipOptions = relationshipOptions
            self.onSave = onSave
        }

        var body: some View {
            NavigationView {
                Form {
                    Section(header: Text("New Member Details")) {
                        TextField("Name*", text: $nameState)
                            .textFieldStyle(PlainTextFieldStyle())
                        Picker("Relationship*", selection: $relationshipState) {
                            ForEach(relationshipOptions, id: \.self) { option in
                                Text(option.capitalized).tag(option)
                            }
                        }
                        TextField("Email (Optional)", text: $emailState)
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                            .textFieldStyle(PlainTextFieldStyle())
                        TextField("Phone (Optional)", text: $phoneState)
                            .keyboardType(.phonePad)
                            .textFieldStyle(PlainTextFieldStyle())
                        
                        Text("Date of Birth (Month & Year)")
                            .font(.caption).foregroundColor(.gray)
                        AccountView.MonthYearPicker(selectedMonth: $dobMonthState, selectedYear: $dobYearState) // Use AccountView.MonthYearPicker if nested
                    }
                    
                    Button("Add This Member") {
                        if nameState.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            // Optionally show an alert for required fields
                            print("Name is required for new family member.")
                            return
                        }
                        
                        let dobString = String(format: "%04d-%02d", dobYearState, dobMonthState)
                        
                        onSave((
                            name: nameState,
                            relationship: relationshipState,
                            email: emailState.isEmpty ? nil : emailState,
                            phone: phoneState.isEmpty ? nil : phoneState,
                            dob: dobString
                        ))
                        isPresented = false
                    }
                    .disabled(nameState.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .navigationTitle("Add New Family Member")
                .navigationBarTitleDisplayMode(.inline)
                .navigationBarItems(leading: Button("Cancel") { isPresented = false })
            }
        }
    }
    private static let accountViewIsoDateTimeFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        // This configuration should be robust enough for typical full date-time strings
        // It tries to be lenient by default by not specifying .withFractionalSeconds.
        // If your expiry dates ALWAYS have fractional seconds, add .withFractionalSeconds.
        // If they sometimes do, sometimes don't, this might need more logic OR the string might be pre-processed.
        formatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime, .withTimeZone, .withFractionalSeconds]
        return formatter
    }()
    
    private static let accountViewDateOnlyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0) // Assuming UTC for date-only strings if not specified
        return formatter
    }()
    
    private static let yearMonthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0) // Or your app's default
        return formatter
    }()
    
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
            // MARK: - ADD THIS ALERT MODIFIER FOR DELETE CONFIRMATION
                .alert("Confirm Deletion", isPresented: $showDeleteFamilyMemberConfirmation, presenting: familyMemberToDelete) { memberToDeleteDetails in
                    // 'memberToDeleteDetails' is the non-nil 'familyMemberToDelete' passed to the alert
                    Button("Delete \(memberToDeleteDetails.name)", role: .destructive) {
                        confirmAndDeleteFamilyMember() // Call your action function
                    }
                    Button("Cancel", role: .cancel) {
                        self.familyMemberToDelete = nil // Important: Clear selection if user cancels
                    }
                } message: { memberToDeleteDetails in
                    Text("Are you sure you want to delete \(memberToDeleteDetails.name)? This action cannot be undone.")
                }
        }
        .sheet(item: $approvalURL, onDismiss: {
            approvalURL = nil
            isProcessingMembershipAction = false  // Re-enable button if sheet is dismissed
            if !showPurchaseSuccess { // If PayPal sheet is dismissed early
                // Reset state if payment wasn't completed
                // currentActionIsRenewal can remain as set by the button
                paymentDataFromPayPal = nil
            }
        }) { url in
            PayPalView( // Ensure PayPalView is correctly defined elsewhere
                approvalURL: url,
                showPaymentError: $showPaymentError,
                paymentErrorMessage: $paymentErrorMessage,
                showPurchaseSuccess: $showPurchaseSuccess,
                paymentConfirmationData: $paymentDataFromPayPal, // Pass the binding
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
            if membershipOptions.isEmpty { // Ensure a default selection if options load later
                fetchPackages()
            } else if selectedPackageIndex >= membershipOptions.count && !membershipOptions.isEmpty {
                selectedPackageIndex = 0
            }
            if let firstDOB = family.first?.dob, !firstDOB.isEmpty {
                let components = firstDOB.split(separator: "-")
                if components.count == 2,
                   let year = Int(components[0]),
                   let month = Int(components[1]) {
                    editYear = year
                    editMonth = month
                }
            }
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
                    .disabled(isUpdating || isProcessingMembershipAction)
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
                                Text("\(pkg.years_of_validity)-year: $\(Int(pkg.amount))").tag(idx)
                            }
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle()).padding(.vertical, 8)
                    
                    HStack {
                        Spacer()
                        Button(action: {
                            self.isProcessingMembershipAction = true
                            guard selectedPackageIndex < membershipOptions.count else {
                                paymentErrorMessage = "Please select a valid membership package."
                                showPaymentError = true
                                self.isProcessingMembershipAction = false // Reset on early exit
                                return
                            }
                            let pkg = membershipOptions[selectedPackageIndex]
                            
                            // This is the 'item' name for PayPal, specific to membership
                            let itemTitleForMembership = "NEMA Membership - \(pkg.years_of_validity) Year"
                            
                            // Determine the type: "renew" or "new_member" (or "membership" if your backend handles that as new)
                            let effectiveMembershipType = profileData.isMember ? "renew" : "new_member"
                            self.currentActionIsRenewal = (effectiveMembershipType == "renew") // Set the flag
                            self.paymentDataFromPayPal = nil // Reset any previous data
                            
                            print("[AccountView] MEMBER_ACTION_TRACE: Type: \(effectiveMembershipType), Profile ID: \(profileData.id), Pkg ID: \(pkg.id)")
                            
                            // Call PaymentManager with the parameter names defined in YOUR PaymentManager.swift
                            PaymentManager.shared.createOrder(
                                amount: "\(Int(pkg.amount))",
                                eventTitle: itemTitleForMembership,  // Use 'eventTitle' as per your PaymentManager.swift
                                eventID: nil,                       // No eventID for membership
                                email: profileData.email,
                                name: profileData.name,
                                phone: profileData.phone,
                                membershipType: effectiveMembershipType, // Use 'membershipType' as per your PaymentManager.swift
                                packageId: pkg.id,
                                packageYears: pkg.years_of_validity,
                                userId: profileData.id,             // This is users.id
                                panthiId: nil,                      // No panthiId for membership
                                //  lineItems: nil, // Not passing lineItems for membership
                                completion: { result in
                                    DispatchQueue.main.async {
                                        self.isProcessingMembershipAction = false
                                        switch result {
                                        case .success(let url):
                                            self.approvalURL = url
                                        case .failure(let err):
                                            self.isProcessingMembershipAction = false // Explicitly reset on direct failure
                                            self.handlePaymentManagerError(err, context: "membership payment")
                                        }
                                    }
                                }
                            )
                        }) {
                            
                            if isProcessingMembershipAction {
                                HStack (spacing: 5) {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white)) // Assuming white text on orange button
                                    Text("Processing...")
                                }
                            } else {
                                Text(profileData.isMember ? "Renew Membership" : "Become a Member")
                            }
                        }
                        .font(.subheadline)
                        .padding(.horizontal, 10) // Adjusted padding for "smaller" feel
                        .padding(.vertical, 6)
                        .background(isProcessingMembershipAction ? Color.gray : Color.orange) // Background changes if processing
                        .foregroundColor(.white)
                        .cornerRadius(6)
                        .disabled(isProcessingMembershipAction || isUpdating) // Disable when processing or other updates
                        Spacer()
                    }
                } else {
                    ProgressView("Loading membership options...").padding(.vertical)
                }
            }
            .padding()
            .background(Color(.secondarySystemBackground)).cornerRadius(16)
            .padding(.horizontal)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 0.4) // subtle border
            )
            .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
        }
    }
    private var familySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Your Family").font(.headline)
                Spacer()
                if authToken != nil {
                    if isEditingFamily {
                        // "Add New Member" button
                        Button {
                            // Reset state for the Add Member sheet before showing it
                            self.newMemberName = ""
                            self.newMemberRelationship = self.relationshipOptions.first ?? "spouse" // Default
                            self.newMemberEmail = ""    // Reset to empty or nil
                            self.newMemberPhone = ""    // Reset to empty or nil
                            // Default DOB (e.g., 25 years ago)
                            self.newMemberDOBMonth = Calendar.current.component(.month, from: Date())
                            self.newMemberDOBYear = Calendar.current.component(.year, from: Date()) - 25

                            self.showingAddMemberSheet = true
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .imageScale(.large)
                        }
                        .foregroundColor(.orange)

                        Spacer() // Pushes Save and Done to the right

                        Button("Save All") { // Renamed for clarity, saves all edits
                            saveFamily()
                        }
                        .foregroundColor(.orange)
                        .disabled(isUpdating)

                        Button("Done") { // Renamed for clarity
                            isEditingFamily = false
                            // Optionally, reload family to discard any un-added but edited fields
                            // if your saveFamily doesn't already handle reverting non-submitted changes.
                            // loadFamily()
                        }
                        .foregroundColor(.orange)
                    } else {
                        Button("Manage Family") { // This was "Edit" before
                           isEditingFamily = true
                           isEditingProfile = false
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
                VStack(spacing: 12) { // This VStack will group all family member cards
                    ForEach($family) { $member in
                        VStack(alignment: .leading, spacing: 8) {
                            EditableInfoRow(label: "Name", text: $member.name, isEditing: isEditingFamily)
                            // Relationship picker
                            if isEditingFamily {
                                Button(role: .destructive) {
                                    self.familyMemberToDelete = member // Store the member to delete
                                    self.showDeleteFamilyMemberConfirmation = true // Show confirmation alert
                                } label: {
                                    HStack {
                                        Image(systemName: "trash")
                                      //  Text("Delete This Member")
                                    }
                                    .foregroundColor(.red)
                                    .frame(maxWidth: .infinity, alignment: .center) // Or .trailing if you prefer
                                }
                                .padding(.top, 8) // Add some spacing before the button
                                //}
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Relation:")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                    Picker("Relation", selection: $member.relationship) {
                                        ForEach(relationshipOptions, id: \.self) { option in
                                            Text(option.capitalized).tag(option)
                                        }
                                    }
                                    .pickerStyle(MenuPickerStyle())
                                    .padding(.vertical, 4)
                                    .frame(minHeight: 25)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    Divider()
                                }
                            } else {
                                // Revert to VStack for stacked display when not editing, to match Screenshot 2
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Relation:") // Label
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                    Text(member.relationship.capitalized) // Value
                                        .font(.subheadline)
                                        .foregroundColor(.primary) // Or your desired color for values
                                        .padding(.vertical, 4) // Match padding if EditableInfoRow has it
                                }
                                // Divider()
                            }
                            
                            // Phone field
                            EditableInfoRow(label: "Phone", text: Binding(
                                get: { member.phone ?? "" }, set: { member.phone = $0.isEmpty ? nil : $0 }
                            ), isEditing: isEditingFamily, keyboardType: .phonePad)
                            
                            EditableInfoRow(label: "Email", text: Binding(
                                get: { member.email ?? "" }, set: { member.email = $0.isEmpty ? nil : $0 }
                            ), isEditing: isEditingFamily, keyboardType: .emailAddress)
                            
                            // DOB picker
                            if isEditingFamily {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("DOB (Month & Year):*")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                    
                                    MonthYearPicker(
                                        selectedMonth: Binding(
                                            get: { editingDOB[member.id]?.month ?? currentMonth(from: member.dob) },
                                            set: { editingDOB[member.id, default: (currentMonth(from: member.dob), currentYear(from: member.dob))].month = $0 }
                                        ),
                                        selectedYear: Binding(
                                            get: { editingDOB[member.id]?.year ?? currentYear(from: member.dob) },
                                            set: { editingDOB[member.id, default: (currentMonth(from: member.dob), currentYear(from: member.dob))].year = $0 }
                                        )
                                    )
                                    .padding(.vertical, 1)
                                    Divider()
                                }
                            } else { // ✅ ADD THIS BLOCK
                                if let dob = member.dob, !dob.isEmpty {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("DOB:")
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                        Text(formattedDOB(from: member.dob))
                                            .font(.subheadline)
                                            .padding(.vertical, 4)
                                    }
                                }
                            }
                            
                        }
                        .padding() // Inner padding for content within the card
                        .frame(maxWidth: .infinity, alignment: .leading) // Make VStack take full width
                        .background(Color(.secondarySystemBackground)) // Apply background to full-width VStack
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.gray.opacity(0.2), lineWidth: 0.4) // subtle border
                        )
                        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
                    }
                }
                .padding(.horizontal) // Apply horizontal padding to the group of cards
            }
        }
        .sheet(isPresented: $showingAddMemberSheet) {
            // Ensure AddFamilyMemberSheetView is correctly defined and accessible
            // And that AccountView.MonthYearPicker is accessible if AddFamilyMemberSheetView is outside AccountView
            AddFamilyMemberSheetView(
                isPresented: $showingAddMemberSheet,
                name: newMemberName, // Pass initial/reset values
                relationship: newMemberRelationship,
                email: newMemberEmail ?? "", // Pass initial/reset values
                phone: newMemberPhone ?? "", // Pass initial/reset values
                dobMonth: newMemberDOBMonth, // Pass initial/reset values
                dobYear: newMemberDOBYear,   // Pass initial/reset values
                relationshipOptions: relationshipOptions
            ) { memberDataToSave in
                // This closure is called when "Add Member" is tapped in the sheet
                self.handleAddNewMember(memberData: memberDataToSave)
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
        for index in family.indices {
            let member = family[index]
            if let dobSelection = editingDOB[member.id] {
                family[index].dob = String(format: "%04d-%02d", dobSelection.year, dobSelection.month)
            }
        }
        
        isUpdating = true
        NetworkManager.shared.updateFamily(family) { result in
            DispatchQueue.main.async {
                isUpdating = false
                switch result {
                case .success():
                    isEditingFamily = false
                    DatabaseManager.shared.saveFamily(family)
                    editingDOB = [:] // reset after saving
                case .failure(let err):
                    handlePaymentManagerError(err, context: "family update")
                }
            }
        }
    }
    

    
    // MARK: - Helper funcitons to parse current DOB
    
    private func formattedDOB(from dob: String?) -> String {
        guard let dob = dob, !dob.isEmpty else { return "—" }
        let components = dob.split(separator: "-")
        guard components.count == 2,
              let year = Int(components[0]),
              let month = Int(components[1]),
              (1...12).contains(month) else {
            return "—"
        }
        let monthName = Calendar.current.monthSymbols[month - 1]
        return "\(monthName) \(year)"
    }
    
    private func currentYear(from dob: String?) -> Int {
        guard let dob = dob else { return Calendar.current.component(.year, from: Date()) }
        return Int(dob.prefix(4)) ?? Calendar.current.component(.year, from: Date())
    }
    
    private func currentMonth(from dob: String?) -> Int {
        guard let dob = dob else { return Calendar.current.component(.month, from: Date()) }
        let components = dob.split(separator: "-")
        if components.count > 1, let month = Int(components[1]) {
            return month
        }
        return Calendar.current.component(.month, from: Date())
    }
    
    // MARK: – Date formatting helpers
    
    private func formatDate(_ dateString: String) -> String {
        // Try full ISO8601 date-time first
        if let date = AccountView.accountViewIsoDateTimeFormatter.date(from: dateString) {
            return longStyle(date)
        }
        // Then try date-only "yyyy-MM-dd"
        if let date = AccountView.accountViewDateOnlyFormatter.date(from: dateString) {
            return longStyle(date)
        }
        // Fallback for "yyyy-MM"
        if dateString.count == 7 && dateString.contains("-") {
            let monthFormatter = DateFormatter()
            monthFormatter.dateFormat = "yyyy-MM"
            monthFormatter.locale = Locale(identifier: "en_US_POSIX")
            if let date = monthFormatter.date(from: dateString) {
                let outputFormatter = DateFormatter()
                outputFormatter.dateFormat = "MMMM yyyy" // e.g., "September 2025"
                outputFormatter.locale = Locale(identifier: "en_US_POSIX")
                return outputFormatter.string(from: date)
            }
        }
        print("⚠️ [AccountView.formatDate] Could not parse dateString: \(dateString) with any known format.")
        return dateString // Fallback if no format matches
    }
    private func longStyle(_ date: Date) -> String {
        let out = DateFormatter(); out.dateStyle = .long; out.timeStyle = .none; return out.string(from: date)
    }
    
    
    private func handlePaymentSuccess() {
        print("✅ PayPal Payment Confirmed. Finalizing membership on backend.")
        
        guard let confirmationData = paymentDataFromPayPal,
              let onlinePaymentId = confirmationData.online_payment_db_id else {
            print("⚠️ Confirmation data from PayPal (especially online_payment_db_id) is missing.")
            self.updateErrorMessage = "Could not finalize membership: Missing critical payment confirmation details."
            self.showErrorAlert = true
            self.isProcessingMembershipAction = false
            self.loadAllData()
            self.paymentDataFromPayPal = nil
            return
        }
        
        let packageIdToUse: Int
        let actionTypeString: String
        
        if self.currentActionIsRenewal {
            guard let confirmedPackageId = confirmationData.package_id_for_renewal else {
                print("⚠️ package_id_for_renewal is missing in confirmationData for RENEWAL.")
                self.updateErrorMessage = "Could not finalize membership renewal: Missing package confirmation."
                self.showErrorAlert = true
                self.isProcessingMembershipAction = false // Reset before returning
                self.loadAllData()
                self.paymentDataFromPayPal = nil
                return
            }
            packageIdToUse = confirmedPackageId
            actionTypeString = "renewal"
            print("ℹ️ Finalizing RENEWAL. Package ID from confirmation: \(packageIdToUse). OnlinePaymentID: \(onlinePaymentId)")
            NetworkManager.shared.renewMembership(packageId: packageIdToUse, onlinePaymentId: onlinePaymentId) { result in
                DispatchQueue.main.async {
                    // isProcessingMembershipAction is reset within processMembershipUpdateResult
                    self.processMembershipUpdateResult(result, type: actionTypeString)
                }
            }
        } else { // This is a "new_member" action
            guard selectedPackageIndex < membershipOptions.count else {
                print("⚠️ Invalid selectedPackageIndex or empty membershipOptions for NEW membership.")
                self.updateErrorMessage = "Could not finalize new membership: Package selection error."
                self.showErrorAlert = true
                self.isProcessingMembershipAction = false // Reset before returning
                self.loadAllData()
                self.paymentDataFromPayPal = nil
                return
            }
            packageIdToUse = membershipOptions[selectedPackageIndex].id
            actionTypeString = "creation" // For the log message in processMembershipUpdateResult
            print("ℹ️ Finalizing NEW membership. Package ID from local state: \(packageIdToUse). OnlinePaymentID: \(onlinePaymentId)")
            NetworkManager.shared.createMembership(packageId: packageIdToUse, onlinePaymentId: onlinePaymentId) { result in
                DispatchQueue.main.async {
                    // isProcessingMembershipAction is reset within processMembershipUpdateResult
                    self.processMembershipUpdateResult(result, type: actionTypeString)
                }
            }
        }
    }
    
    
    private func processMembershipUpdateResult(_ result: Result<Membership, NetworkError>, type: String) {
        self.isProcessingMembershipAction = false // Reset processing state here, for both success and failure paths of backend call
        switch result {
        case .success(let updatedMembership):
            print("✅ Membership successfully \(type) on backend. New expiry: \(updatedMembership.exp_date)")
        case .failure(let err):
            print("❌ Failed to \(type) membership on backend: \(err.localizedDescription)")
            // handlePaymentManagerError will also set isProcessingMembershipAction = false if context contains "membership"
            // but setting it here ensures it's always reset before the alert might show.
            self.handlePaymentManagerError(err, context: "Membership \(type) finalization")
        }
        self.loadAllData()
        self.paymentDataFromPayPal = nil
    }
    
    
    private func handlePaymentManagerError(_ error: Error, context: String = "operation") {
        // Ensure isProcessingMembershipAction is reset if an error occurs during a membership action
        // This is a fallback, primary reset should be in processMembershipUpdateResult or direct call sites.
        if context.lowercased().contains("membership") && self.isProcessingMembershipAction {
            print("ℹ️ [handlePaymentManagerError] Resetting isProcessingMembershipAction due to error in: \(context)")
            self.isProcessingMembershipAction = false
        }
        
        if let paymentErr = error as? PaymentError { // Assuming PaymentError is your custom enum
            switch paymentErr {
            case .serverError(let msg): updateErrorMessage = "Server Error (\(context)): \(msg)"
            case .invalidResponse: updateErrorMessage = "Invalid Response (\(context))."
            case .parseError(let msg): updateErrorMessage = "Parse Error (\(context)): \(msg)"
            }
        } else if let networkErr = error as? NetworkError {
            switch networkErr {
            case .serverError(let msg): updateErrorMessage = "Network Error (\(context)): \(msg)"
            case .invalidResponse: updateErrorMessage = "Invalid Network Response (\(context))."
            case .decodingError(let decErr): updateErrorMessage = "Data Error (\(context)): \(decErr.localizedDescription)"
            }
        } else {
            updateErrorMessage = "Error during \(context): \(error.localizedDescription)"
        }
        showErrorAlert = true
    }
    
    // MARK: – Data Loading
    
    private func loadAllData() {
        print("🔄 [AccountView] loadAllData called.")
        if self.profile == nil { // Only load from cache if profile isn't already set (e.g. from a previous load)
            loadLocalProfile()
        }
        
        loadRemoteProfile()  // This calls loadMembership internally on success
        loadFamily()
        fetchPackages()  // Fetch available membership packages
    }
    
    private func fetchPackages() {
        NetworkManager.shared.fetchMembershipPackages { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let packs):
                    self.membershipOptions = packs
                    if !packs.isEmpty {
                        // Ensure selectedPackageIndex is valid, default to 0 if out of bounds or if current selection is no longer valid
                        if self.selectedPackageIndex >= packs.count || self.selectedPackageIndex < 0 {
                            self.selectedPackageIndex = 0
                        }
                    } else {
                        self.selectedPackageIndex = 0 // No options, so index must be 0
                    }
                case .failure(let err):
                    print("⚠️ Failed to load membership packages: \(err.localizedDescription)")
                }
            }
        }
    }
    
    private func loadMembership() {
        guard let effectiveProfileID = self.profile?.id, effectiveProfileID != 0 else {
            print("ℹ️ [AccountView.loadMembership] No valid user profile ID (current self.profile is nil or ID is 0), cannot fetch membership.")
            if self.cachedExpiryRaw != nil { self.cachedExpiryRaw = nil } // Clear if no valid profile to associate with
            if self.membershipId != nil { self.membershipId = nil }
            if var p = self.profile, p.membershipExpiryDate != nil { // Only update if there's a change
                p.membershipExpiryDate = nil
                self.profile = p
                DatabaseManager.shared.saveUser(p)
            }
            return
        }
        
        print("ℹ️ [AccountView.loadMembership] Fetching membership for User ID: \(effectiveProfileID)")
        NetworkManager.shared.fetchMembership { result in
            DispatchQueue.main.async {
                var serverExpiryDate: String? = nil
                switch result {
                case .success(let membership):
                    if membership.user_id == effectiveProfileID {
                        print("✅ [AccountView.loadMembership] Fetched membership. DB Expiry: \(membership.exp_date), UserID in record: \(membership.user_id)")
                        serverExpiryDate = membership.exp_date
                        self.membershipId = membership.id
                    } else {
                        print("⚠️ [AccountView.loadMembership] Fetched membership's user_id (\(membership.user_id)) does not match current profile ID (\(effectiveProfileID)). Ignoring this membership data.")
                        // This implies the membership data is not for the current user, so treat as no membership found.
                        serverExpiryDate = nil
                    }
                case .failure(let err):
                    print("⚠️ [AccountView.loadMembership] Failed to fetch membership details: \(err.localizedDescription)")
                    // If fetch fails (e.g., 404 if no membership exists), it means no active membership on server.
                    serverExpiryDate = nil
                }
                
                // Update AppStorage and @State profile *only after* getting a definitive server response (success or failure indicating no membership)
                self.cachedExpiryRaw = serverExpiryDate // Update @AppStorage with server's truth (could be nil)
                
                if var p = self.profile, p.id == effectiveProfileID { // Ensure we're updating the correct profile
                    if p.membershipExpiryDate != serverExpiryDate {
                        p.membershipExpiryDate = serverExpiryDate
                        self.profile = p // Update @State to trigger UI
                        DatabaseManager.shared.saveUser(p) // Persist the updated profile
                        print("✅ [AccountView.loadMembership] Updated self.profile.membershipExpiryDate with server value: \(serverExpiryDate ?? "nil")")
                    }
                }
            }
        }
    }
    
    private func loadLocalProfile() {
        if let cachedUser = DatabaseManager.shared.currentUser {
            // Only update self.profile if it's nil or different, to reduce needless view updates.
            var shouldUpdateProfileState = self.profile == nil
            if let currentP = self.profile, currentP.id != cachedUser.id || currentP.name != cachedUser.name {
                shouldUpdateProfileState = true
            }
            
            if shouldUpdateProfileState {
                self.profile = cachedUser
            }
            // Prime cachedExpiryRaw from the local UserProfile if it's not already set by a more recent server fetch
            if self.cachedExpiryRaw == nil, let localExpiry = cachedUser.membershipExpiryDate {
                self.cachedExpiryRaw = localExpiry
            }
            self.userId = cachedUser.id
            print("ℹ️ [AccountView.loadLocalProfile] Profile set from cache: \(cachedUser.name). Current cachedExpiryRaw: \(self.cachedExpiryRaw ?? "nil")")
        } else {
            print("ℹ️ [AccountView.loadLocalProfile] No profile in cache.")
            self.profile = nil // Ensure profile is nil if nothing in cache
            self.cachedExpiryRaw = nil // And clear cached expiry
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
                case .success(var freshProfile):
                    if freshProfile.membershipExpiryDate == nil {
                        if let existingProfileExpiry = self.profile?.membershipExpiryDate {
                            print("ℹ️ [AccountView.loadRemoteProfile] Fetched profile lacks expiry, preserving current self.profile.membershipExpiryDate: \(existingProfileExpiry)")
                            freshProfile.membershipExpiryDate = existingProfileExpiry
                        } else if let cachedRaw = self.cachedExpiryRaw {
                            // Fallback to @AppStorage if current self.profile also had no expiry
                            print("ℹ️ [AccountView.loadRemoteProfile] Fetched profile lacks expiry, self.profile also lacks, using cachedExpiryRaw: \(cachedRaw)")
                            freshProfile.membershipExpiryDate = cachedRaw
                        }
                    }
                    DatabaseManager.shared.saveUser(freshProfile)
                    self.profile = freshProfile
                    if freshProfile.id != 0 { // Ensure userId is valid before setting
                        self.userId = freshProfile.id
                    }
                    print("✅ [AccountView.loadRemoteProfile] Fetched/Updated remote profile: \(freshProfile.name), ID: \(freshProfile.id). Profile's current expiry for UI (pre-loadMembership): \(self.profile?.membershipExpiryDate ?? "nil")")
                    
                case .failure(let err):
                    print("⚠️ [AccountView] Failed to fetch remote profile: \(err.localizedDescription)")
                    if case NetworkError.invalidResponse = err { // e.g. 401 Unauthorized
                        print("‼️ Session might have expired. Clearing auth token.")
                        self.authToken = nil // Trigger re-login
                        return
                    }
                }
                self.loadMembership()
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
    
    private func confirmAndDeleteFamilyMember() {
        guard let memberToDelete = self.familyMemberToDelete else {
            print("⚠️ Attempted to delete but familyMemberToDelete was nil.")
            return
        }
        
        // Check for authToken, as form POSTs to web routes usually rely on an active session cookie
        guard self.authToken != nil else { // authToken is your @AppStorage("laravelSessionToken")
            self.updateErrorMessage = "Your session may have expired. Please log out and log back in."
            self.showErrorAlert = true
            self.familyMemberToDelete = nil // Clear selection
            return
        }
        
        isUpdating = true // Show a loading indicator (reuses your existing @State var)
        
        NetworkManager.shared.deleteFamilyMember(memberId: memberToDelete.id) { result in // Calling the function from NetworkManager
            DispatchQueue.main.async {
                isUpdating = false
                switch result {
                case .success:
                    print("✅ Successfully processed delete request for member \(memberToDelete.name) (ID: \(memberToDelete.id)) by backend.")
                    // Remove the member from the local 'family' array for immediate UI update
                    family.removeAll { $0.id == memberToDelete.id }
                    
                    // Optionally, clear other related states
                    editingDOB.removeValue(forKey: memberToDelete.id) // Clear any DOB editing state for this member
                    self.familyMemberToDelete = nil // Clear the member marked for deletion
                    self.isEditingFamily = false
                    
                    // You might want to inform the user locally, though the main feedback
                    // for web-based operations is often the reloaded page state.
                    // For a native app, a small success message can be good.
                    // Example: self.updateErrorMessage = "\(memberToDelete.name) has been deleted."
                    //          self.showSomeSuccessAlert = true // (You'd need a new @State for this)
                    
                case .failure(let error):
                    var errorMessageToShow = "Could not delete \(memberToDelete.name)."
                    if let networkErr = error as? NetworkError {
                         switch networkErr {
                         case .serverError(let msg): errorMessageToShow += " Server error: \(msg)"
                         case .invalidResponse: errorMessageToShow += " Invalid server response."
                         case .decodingError(let decErr): errorMessageToShow += " Data error: \(decErr.localizedDescription)"
                         }
                    } else {
                        errorMessageToShow += " Specific error: \(error.localizedDescription)"
                    }
                    self.updateErrorMessage = errorMessageToShow
                    self.showErrorAlert = true
                    self.familyMemberToDelete = nil
                }
            }
        }
    }
    
    private func handleAddNewMember(memberData: (name: String, relationship: String, email: String?, phone: String?, dob: String) ) {
        // authToken check is good practice
        guard self.authToken != nil else {
            self.updateErrorMessage = "Your session may have expired. Please log out and log back in."
            self.showErrorAlert = true
            return
        }
        
        isUpdating = true // Show loading indicator
        
        NetworkManager.shared.addNewFamilyMember(
            name: memberData.name,
            relationship: memberData.relationship,
            email: memberData.email,
            dob: memberData.dob, // Already formatted as "YYYY-MM" by AddFamilyMemberSheetView
            phone: memberData.phone
        ) { result in
            DispatchQueue.main.async {
                self.isUpdating = false // Hide loading indicator
                switch result {
                case .success:
                    print("✅ Successfully initiated add new family member '\(memberData.name)' via backend.")
                    // The backend typically redirects after adding, which should trigger a page reload on web.
                    // For the app, explicitly reload the family list to show the new member.
                    self.loadFamily()
                    
                    // Optionally, provide a success message to the user through an alert or other UI.
                    // self.updateErrorMessage = "\(memberData.name) has been successfully added to your family."
                    // self.showSomeSuccessAlert = true // (You would need a new @State for this type of alert)

                case .failure(let error):
                    var errorMessageToShow = "Could not add \(memberData.name)."
                    if let networkErr = error as? NetworkError {
                         switch networkErr {
                         case .serverError(let msg): errorMessageToShow += " Server error: \(msg)"
                         case .invalidResponse: errorMessageToShow += " Invalid server response."
                         case .decodingError(let decErr): errorMessageToShow += " Data error: \(decErr.localizedDescription)"
                         }
                    } else {
                        errorMessageToShow += " Specific error: \(error.localizedDescription)"
                    }
                    self.updateErrorMessage = errorMessageToShow
                    self.showErrorAlert = true // Use your existing error alert mechanism
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
                        .frame(minHeight: 25)
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
}
