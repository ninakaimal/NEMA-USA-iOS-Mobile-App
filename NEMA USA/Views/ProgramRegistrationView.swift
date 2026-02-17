//  ProgramRegistrationView.swift
//  NEMA USA
//  Created by Arjun on 6/14/25.
//

import SwiftUI
import UIKit

// MARK: - ViewModel
@MainActor
class ProgramRegistrationViewModel: ObservableObject {
    @Published var eligibleParticipants: [FamilyMember] = []
    @Published var selectedParticipantIDs = Set<Int>()
    @Published var selectedPracticeLocationId: Int? = nil
    @Published var comments: String = ""
    @Published var acceptedTerms = false
    @Published var guestName: String = ""
    @Published var guestAgeText: String = ""
    
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var registrationSuccess = false
    
    // PayPal-related properties
    @Published var isProcessingPayment = false
    @Published var showPaymentError = false
    @Published var paymentErrorMessage = ""
    @Published var showPurchaseSuccess = false
    @Published var approvalURL: URL? = nil
    @Published var paymentConfirmationData: PaymentConfirmationResponse? = nil

    private let networkManager = NetworkManager.shared

    private var trimmedGuestName: String { guestName.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedGuestAgeText: String { guestAgeText.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var guestAgeValue: Int? {
        guard let age = Int(trimmedGuestAgeText), age > 0 else { return nil }
        return age
    }
    var hasGuestInput: Bool { !trimmedGuestName.isEmpty || !trimmedGuestAgeText.isEmpty }
    var guestInputError: String? {
        guard hasGuestInput else { return nil }
        if trimmedGuestName.isEmpty { return "Enter guest name" }
        guard guestAgeValue != nil else { return "Enter a valid age" }
        return nil
    }
    var guestPayload: [String: Any]? {
        guard guestInputError == nil, hasGuestInput, let age = guestAgeValue else { return nil }
        return ["name": trimmedGuestName, "age": age]
    }
    var hasAnyParticipantSelection: Bool {
        !selectedParticipantIDs.isEmpty || guestPayload != nil
    }
    var totalParticipantCount: Int {
        let guestCount = guestPayload != nil ? 1 : 0
        return selectedParticipantIDs.count + guestCount
    }
    func perParticipantAmount(for program: EventProgram, isMember: Bool) -> Double {
        program.price(isMember: isMember)
    }
    func totalChargeAmount(for program: EventProgram, isMember: Bool) -> Double {
        let participantCount = totalParticipantCount
        guard participantCount > 0 else { return 0 }
        let perParticipant = perParticipantAmount(for: program, isMember: isMember)
        return perParticipant * Double(participantCount)
    }
    
    func canSubmit(for program: EventProgram) -> Bool {
        guard hasAnyParticipantSelection && acceptedTerms else { return false }
        guard guestInputError == nil else { return false }
        if let locations = program.practiceLocations, !locations.isEmpty {
            guard selectedPracticeLocationId != nil else { return false }
        }
        if categoryStatus(for: program).errorMessage != nil {
            return false
        }
        return true
    }
    
    // ENHANCED: Additional validation for paid programs
    func canSubmitWithPayment(for program: EventProgram, name: String, email: String, phone: String) -> (canSubmit: Bool, errorMessage: String?) {
        // Check basic submission requirements
        guard canSubmit(for: program) else {
            return (false, "Please complete all required fields and accept terms")
        }
        
        // For paid programs, validate payment information
        if program.isPaidProgram {
            guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return (false, "Please provide your full name")
            }
            
            guard !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return (false, "Please provide your email address")
            }
            
            guard email.isValidEmail else {
                return (false, "Please provide a valid email address")
            }
            
            guard !phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return (false, "Please provide your phone number")
            }
            
            // Validate minimum phone length
            let cleanPhone = phone.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
            guard cleanPhone.count >= 10 else {
                return (false, "Please provide a valid phone number")
            }
        }
        
        return (true, nil)
    }
    
    func categoryStatus(for program: EventProgram) -> (category: ProgramCategory?, errorMessage: String?) {
        guard !program.categories.isEmpty else { return (nil, nil) }
        if !hasAnyParticipantSelection { return (nil, nil) }
        var resolvedCategory: ProgramCategory?
        var mismatchedNames: [String] = []
        var missingAgeNames: [String] = []
        var outOfRangeNames: [String] = []
        let categories = program.categories
        
        func processParticipant(name: String, age: Int?) {
            guard let age else {
                missingAgeNames.append(name)
                return
            }
            guard let category = matchCategory(forAge: age, categories: categories) else {
                outOfRangeNames.append(name)
                return
            }
            if let current = resolvedCategory {
                if current.id != category.id {
                    mismatchedNames.append(name)
                }
            } else {
                resolvedCategory = category
            }
        }
        
        for id in selectedParticipantIDs {
            if let member = eligibleParticipants.first(where: { $0.id == id }) {
                processParticipant(name: member.name, age: age(for: member))
            }
        }
        
        if let guest = guestPayload {
            let guestName = (guest["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let label = guestName?.isEmpty == false ? guestName! : "Guest participant"
            let guestAge = guest["age"] as? Int
            processParticipant(name: label, age: guestAge)
        }
        
        if !missingAgeNames.isEmpty {
            let list = missingAgeNames.joined(separator: ", ")
            return (resolvedCategory, "Add birthdates/ages for: \(list) so we can verify the category.")
        }
        
        if !outOfRangeNames.isEmpty {
            let list = outOfRangeNames.joined(separator: ", ")
            return (resolvedCategory, "Selected ages do not match any category for: \(list).")
        }
        
        if !mismatchedNames.isEmpty {
            let list = mismatchedNames.joined(separator: ", ")
            return (resolvedCategory, "All participants must be in the same age bracket. Remove or register separately for: \(list).")
        }
        
        return (resolvedCategory, nil)
    }
    
    private func age(for member: FamilyMember) -> Int? {
        guard let dob = member.dob, !dob.isEmpty else { return nil }
        let components = dob.split(separator: "-")
        guard let year = Int(components.first ?? "") else { return nil }
        let month = components.count > 1 ? Int(components[1]) ?? 1 : 1
        var dateComponents = DateComponents()
        dateComponents.year = year
        dateComponents.month = month
        let calendar = Calendar.current
        guard let birthDate = calendar.date(from: dateComponents) else { return nil }
        let now = Date()
        return calendar.dateComponents([.year], from: birthDate, to: now).year
    }
    
    private func matchCategory(forAge age: Int, categories: [ProgramCategory]) -> ProgramCategory? {
        guard !categories.isEmpty else { return nil }
        for category in categories {
            let minOk = category.minAge.map { age >= $0 } ?? true
            let maxOk = category.maxAge.map { age <= $0 } ?? true
            if minOk && maxOk { return category }
        }
        return nil
    }

    func loadData(for programId: String) async {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        
        do {
            let fetchedParticipants = try await networkManager.getEligibleParticipants(forProgramId: programId)
            await MainActor.run {
                self.eligibleParticipants = fetchedParticipants
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                // Enhanced error handling with specific messages
                if let networkError = error as? NetworkError {
                    switch networkError {
                    case .serverError(let message):
                        if message.contains("401") || message.contains("unauthorized") {
                            self.errorMessage = "Session expired. Please log out and log back in."
                        } else {
                            self.errorMessage = "Server error: \(message)"
                        }
                    case .invalidResponse:
                        self.errorMessage = "Unable to connect to server. Please check your internet connection."
                    case .decodingError:
                        self.errorMessage = "Received invalid data from server. Please try again."
                    }
                } else {
                    self.errorMessage = "Failed to load participants: \(error.localizedDescription)"
                }
                self.isLoading = false
            }
        }
    }

    func submitRegistration(for eventId: String, program: EventProgram) async {
        guard canSubmit(for: program) else { return }
        
        if let locations = program.practiceLocations, !locations.isEmpty, selectedPracticeLocationId == nil {
            await MainActor.run {
                errorMessage = "Please select a practice location"
            }
            return
        }
        
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        
        do {
            print("[ProgramRegistration] Submitting program register request:")
            print("  participants: \(Array(selectedParticipantIDs))")
            print("  guest: \(String(describing: guestPayload))")
            print("  practiceLocationId: \(String(describing: selectedPracticeLocationId))")
            try await networkManager.registerForProgram(
                eventId: eventId,
                programId: program.id,
                participantIds: Array(selectedParticipantIDs),
                practiceLocationId: selectedPracticeLocationId,
                comments: comments,
                guestParticipant: guestPayload
            )
            await MainActor.run {
                self.registrationSuccess = true
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                // Enhanced error handling for registration
                if let networkError = error as? NetworkError {
                    switch networkError {
                    case .serverError(let message):
                        if message.contains("401") || message.contains("unauthorized") {
                            self.errorMessage = "Session expired. Please log out and log back in."
                        } else if message.contains("404") {
                            self.errorMessage = "Program registration is no longer available."
                        } else if message.contains("already registered") {
                            self.errorMessage = "You are already registered for this program."
                        } else {
                            self.errorMessage = "Registration failed: \(message)"
                        }
                    case .invalidResponse:
                        self.errorMessage = "Unable to connect to server. Please check your internet connection and try again."
                    case .decodingError:
                        self.errorMessage = "Registration may have succeeded, but we couldn't confirm it. Please check 'My Events' to verify."
                    }
                } else {
                    self.errorMessage = "Registration failed: \(error.localizedDescription)"
                }
                self.registrationSuccess = false
                self.isLoading = false
            }
        }
    }
    
    func initiatePayment(for program: EventProgram, event: Event, memberName: String, email: String, phone: String) {
        // Comprehensive validation before payment
        let validation = canSubmitWithPayment(for: program, name: memberName, email: email, phone: phone)
        guard validation.canSubmit else {
            paymentErrorMessage = validation.errorMessage ?? "Please complete all required information"
            showPaymentError = true
            return
        }
        
        guard let currentUser = DatabaseManager.shared.currentUser else {
            paymentErrorMessage = "User authentication required for payment. Please log out and log back in."
            showPaymentError = true
            return
        }
        
        // Validate program pricing
        let isMember = currentUser.isMember
        let perParticipantAmount = program.price(isMember: isMember)
        
        guard perParticipantAmount > 0 else {
            paymentErrorMessage = "Invalid program pricing. Please contact support."
            showPaymentError = true
            return
        }
        
        let participantCount = totalParticipantCount
        guard participantCount > 0 else {
            paymentErrorMessage = "Select at least one participant before paying."
            showPaymentError = true
            return
        }
        
        let totalAmount = perParticipantAmount * Double(participantCount)
        
        // Check for active internet connection (basic check)
        guard NetworkMonitor.shared.isConnected else {
            paymentErrorMessage = "No internet connection. Please check your connection and try again."
            showPaymentError = true
            return
        }
        
        isProcessingPayment = true
        
        PaymentManager.shared.createOrder(
            amount: String(format: "%.2f", totalAmount),
            eventTitle: "\(program.name) Registration",
            eventID: Int(event.id),
            email: email,
            name: memberName,
            phone: phone,
            membershipType: nil,
            packageId: Int(program.id),
            packageYears: nil,
            userId: currentUser.id,
            panthiId: nil,
            lineItems: nil,
            participantIds: Array(selectedParticipantIDs),
            guestParticipant: guestPayload
        ) { result in
            DispatchQueue.main.async {
                self.isProcessingPayment = false
                switch result {
                case .success(let url):
                    if let url = url {
                        // Regular payment with PayPal URL
                        guard url.scheme == "https" else {
                            self.paymentErrorMessage = "Invalid payment URL received"
                            self.showPaymentError = true
                            return
                        }
                        self.approvalURL = url
                    } else {
                        // Programs always need payment, so nil URL is an error
                        self.paymentErrorMessage = "Payment setup failed - no payment URL received"
                        self.showPaymentError = true
                    }
                    
                case .failure(let error):
                    // Comprehensive error handling for payment creation
                    var friendlyMessage = "Unable to process payment. "
                    
                    if let paymentErr = error as? PaymentError {
                        switch paymentErr {
                        case .serverError(let specificMsg):
                            if specificMsg.contains("network") || specificMsg.contains("timeout") {
                                friendlyMessage += "Please check your internet connection and try again."
                            } else if specificMsg.contains("invalid") {
                                friendlyMessage += "Payment information is invalid. Please contact support."
                            } else {
                                friendlyMessage += "Server error: \(specificMsg)"
                            }
                        case .invalidResponse:
                            friendlyMessage += "Invalid response from payment server. Please try again."
                        case .parseError(_):
                            friendlyMessage += "Error processing payment response. Please contact support if this continues."
                        }
                    } else if let networkErr = error as? NetworkError {
                        switch networkErr {
                        case .serverError(let msg):
                            if msg.contains("401") {
                                friendlyMessage += "Session expired. Please log out and log back in."
                            } else {
                                friendlyMessage += "Server error: \(msg)"
                            }
                        case .invalidResponse:
                            friendlyMessage += "Unable to connect to payment server. Please check your internet connection."
                        case .decodingError:
                            friendlyMessage += "Error processing server response. Please try again."
                        }
                    } else {
                        friendlyMessage += error.localizedDescription
                    }
                    
                    self.paymentErrorMessage = friendlyMessage
                    self.showPaymentError = true
                }
            }
        }
    }
    
    // ENHANCED: Handle successful payment and attempt registration
    func handlePaymentSuccess() {
        guard paymentConfirmationData != nil else {
            paymentErrorMessage = "Payment was successful, but registration confirmation is missing. Please contact support with your payment ID."
            showPaymentError = true
            return
        }
        
        // Here you would normally proceed with registration after successful payment
        // For now, just show success since the current backend doesn't handle program payments
        self.showPurchaseSuccess = true
    }
    
    // ENHANCED: Reset state for retry scenarios
    func resetPaymentState() {
        isProcessingPayment = false
        approvalURL = nil
        paymentConfirmationData = nil
        showPaymentError = false
        paymentErrorMessage = ""
    }
    
    // ENHANCED: Cleanup on dismissal
    func cleanup() {
        resetPaymentState()
        isLoading = false
        errorMessage = nil
        guestName = ""
        guestAgeText = ""
    }
}

// MARK: - Network Monitor (Simple Implementation)
class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()
    @Published var isConnected: Bool = true
    
    private init() {
        // Simple implementation - in a real app, you'd use Network framework
        // For now, assume connected unless proven otherwise
    }
}

// MARK: - Main View
struct ProgramRegistrationView: View {
    let event: Event
    let program: EventProgram
    
    @StateObject private var viewModel = ProgramRegistrationViewModel()
    @Environment(\.presentationMode) private var presentationMode
    
    @State private var memberNameText = ""
    @State private var emailAddressText = ""
    @State private var phoneText = ""
    
    // ENHANCED: Track view state for better error handling
    @State private var hasAppeared = false
    @State private var isRefreshing = false
    @State private var showSuccessAlert = false
    @State private var showPaymentConfirmation = false
    @State private var pendingPaymentInfo: (name: String, email: String, phone: String)? = nil
    
    var body: some View {
        NavigationView {
            if DatabaseManager.shared.jwtApiToken == nil {
                LoginView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Form {
                    // Your Information section is always visible
                    Section(header: HStack {
                        Text("Your Information")
                        if program.requiresPayment {
                            Text("(\(program.formattedPrice))")
                                .foregroundColor(.orange)
                                .font(.caption)
                        }
                    }) {
                        TextField("Full Name", text: $memberNameText)
                            .textFieldStyle(.roundedBorder)
                            .textContentType(.name)
                            .autocapitalization(.words)
                        
                        TextField("Email Address", text: $emailAddressText)
                            .keyboardType(.emailAddress)
                            .textFieldStyle(.roundedBorder)
                            .textContentType(.emailAddress)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                        
                        TextField("Phone Number", text: $phoneText)
                            .keyboardType(.phonePad)
                            .textFieldStyle(.roundedBorder)
                            .textContentType(.telephoneNumber)
                    }
                    
                    // Participant Selection
                    Section(header: Text("Select Participants")) {
                        let categoryStatus = viewModel.categoryStatus(for: program)
                        if viewModel.isLoading && !isRefreshing {
                            ProgressView()
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding()
                        } else if let errorMsg = viewModel.errorMessage {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(errorMsg)
                                    .foregroundColor(.red)
                                    .font(.subheadline)
                                
                                Button("Try Again") {
                                    Task {
                                        isRefreshing = true
                                        await viewModel.loadData(for: program.id)
                                        isRefreshing = false
                                    }
                                }
                                .font(.caption)
                                .foregroundColor(.blue)
                            }
                        } else if viewModel.eligibleParticipants.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("No eligible family members found for this program's age requirements.")
                                    .foregroundColor(.secondary)
                                
                                Button("Refresh") {
                                    Task {
                                        isRefreshing = true
                                        await viewModel.loadData(for: program.id)
                                        isRefreshing = false
                                    }
                                }
                                .font(.caption)
                                .foregroundColor(.blue)
                            }
                        } else {
                            ForEach(viewModel.eligibleParticipants) { member in
                                HStack {
                                    Image(systemName: viewModel.selectedParticipantIDs.contains(member.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(viewModel.selectedParticipantIDs.contains(member.id) ? .orange : .gray)
                                    Text(member.name)
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if viewModel.selectedParticipantIDs.contains(member.id) {
                                        viewModel.selectedParticipantIDs.remove(member.id)
                                    } else {
                                        viewModel.selectedParticipantIDs.insert(member.id)
                                    }
                                }
                            }
                            if let message = categoryStatus.errorMessage {
                                Text(message)
                                    .font(.caption)
                                    .foregroundColor(.red)
                                    .padding(.top, 6)
                            } else if let category = categoryStatus.category, viewModel.hasAnyParticipantSelection {
                                Text("All selected participants fall under \(category.name).")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.top, 6)
                            }
                        }
                    }
                    
                    // Guest Participant (Optional)
                    Section(header: Text("Add Guest Participant (Optional)")) {
                        TextField("Guest Full Name", text: $viewModel.guestName)
                            .textFieldStyle(.roundedBorder)
                            .autocapitalization(.words)
                        TextField("Age", text: $viewModel.guestAgeText)
                            .keyboardType(.numberPad)
                            .textFieldStyle(.roundedBorder)
                        if let guestError = viewModel.guestInputError {
                            Text(guestError)
                                .font(.caption)
                                .foregroundColor(.red)
                        } else if viewModel.hasGuestInput {
                            Text("Use this if you're registering someone outside your family list.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // Practice Location Selection
                    if let locations = program.practiceLocations, !locations.isEmpty {
                        Section(header: HStack {
                            Text("Select Practice Location")
                            Text("*").foregroundColor(.red)
                        }) {
                            Picker("Practice Location", selection: $viewModel.selectedPracticeLocationId) {
                                Text("Select a location").tag(nil as Int?)
                                ForEach(locations) { location in
                                    Text(location.location).tag(location.id as Int?)
                                }
                            }
                            .pickerStyle(MenuPickerStyle())
                            if viewModel.selectedPracticeLocationId == nil && viewModel.acceptedTerms && !viewModel.selectedParticipantIDs.isEmpty {
                                Text("Practice location is required for this program")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                        }
                    }
                    
                    // Comments
                    Section(header: Text("Comments (Optional)")) {
                        TextEditor(text: $viewModel.comments)
                            .frame(height: 80)
                    }


                    TermsDisclosureView(
                        instructionsHTML: program.instructionsHTML,
                        refundPolicyHTML: program.refundPolicyHTML,
                        penaltyDetails: program.penaltyDetails
                    )
                    
                    if program.requiresPayment {
                        Section(header: Text("Payment Summary")) {
                            let isMember = DatabaseManager.shared.currentUser?.isMember ?? false
                            let participantCount = viewModel.totalParticipantCount
                            let perParticipant = viewModel.perParticipantAmount(for: program, isMember: isMember)
                            let totalAmount = viewModel.totalChargeAmount(for: program, isMember: isMember)
                            ProgramPaymentSummaryView(
                                participantCount: participantCount,
                                perParticipantAmount: perParticipant,
                                totalAmount: totalAmount,
                                programName: program.name
                            )
                        }
                    }

                    // Terms
                    Section {
                        Toggle("I accept rules, guidelines and waiver for this program", isOn: $viewModel.acceptedTerms)
                    }
                    
                    // Submit Button
                    Section {
                        Button(action: {
                            if program.requiresPayment {
                                let validation = viewModel.canSubmitWithPayment(
                                    for: program,
                                    name: memberNameText,
                                    email: emailAddressText,
                                    phone: phoneText
                                )
                                
                                if !validation.canSubmit {
                                    viewModel.paymentErrorMessage = validation.errorMessage ?? "Please complete all required information"
                                    viewModel.showPaymentError = true
                                    return
                                }
                                
                                pendingPaymentInfo = (name: memberNameText, email: emailAddressText, phone: phoneText)
                                showPaymentConfirmation = true
                            } else {
                                Task { await viewModel.submitRegistration(for: event.id, program: program) }
                            }
                        }) {
                            HStack {
                                Spacer()
                                if viewModel.isLoading || viewModel.isProcessingPayment {
                                    ProgressView()
                                        .tint(.white)
                                    Text(viewModel.isProcessingPayment ? "Processing Payment..." : "Registering...")
                                        .padding(.leading, 8)
                                } else {
                                    if program.isWaitlistProgram {
                                        Text("Join Waitlist")
                                    } else if program.isPaidProgram { // Keep this for non-waitlist paid programs
                                        let isMember = DatabaseManager.shared.currentUser?.isMember ?? false
                                        let perParticipant = program.price(isMember: isMember)
                                        let selectedCount = viewModel.totalParticipantCount
                                        let totalAmount = perParticipant * Double(max(selectedCount, 1))
                                        let displayAmount = selectedCount > 0 ? totalAmount : perParticipant
                                        Text("Pay $\(String(format: "%.2f", displayAmount)) & Register")
                                    } else {
                                        Text("Register") // For free, non-waitlist programs
                                    }
                                }
                                Spacer()
                            }
                        }
                        .font(.headline.weight(.semibold))
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(viewModel.canSubmit(for: program) ? Color.orange : Color.gray)
                        .cornerRadius(10)
                        .disabled(!viewModel.canSubmit(for: program) || viewModel.isLoading || viewModel.isProcessingPayment)
                        
                        // Helpful validation messages
                        if !viewModel.canSubmit(for: program) && !viewModel.isLoading {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("To register or join waitlist, please:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                if !viewModel.hasAnyParticipantSelection {
                                    Text("• Select a participant or add a guest")
                                        .font(.caption2)
                                        .foregroundColor(.orange)
                                }
                                if let guestError = viewModel.guestInputError {
                                    Text("• \(guestError)")
                                        .font(.caption2)
                                        .foregroundColor(.orange)
                                }
                                
                                if let locations = program.practiceLocations, !locations.isEmpty, viewModel.selectedPracticeLocationId == nil {
                                    Text("• Choose a practice location")
                                        .font(.caption2)
                                        .foregroundColor(.orange)
                                }
                                
                                if let categoryMessage = viewModel.categoryStatus(for: program).errorMessage {
                                    Text("• \(categoryMessage)")
                                        .font(.caption2)
                                        .foregroundColor(.orange)
                                }
                                
                                if !viewModel.acceptedTerms {
                                    Text("• Accept the terms and conditions")
                                        .font(.caption2)
                                        .foregroundColor(.orange)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                        }
                    }
                }
                .navigationTitle(program.name)
                .navigationBarTitleDisplayMode(.inline)
                .navigationBarItems(leading:
                    Button("Cancel") {
                        viewModel.cleanup()
                        presentationMode.wrappedValue.dismiss()
                    }
                    .foregroundColor(.white)
                )
                .task {
                    if !hasAppeared {
                        hasAppeared = true
                        await viewModel.loadData(for: program.id)
                        loadUserInfo()
                    }
                }
                .alert("Success", isPresented: $viewModel.registrationSuccess) {
                    Button("OK", role: .cancel) {
                        viewModel.cleanup()
                        presentationMode.wrappedValue.dismiss()
                    }
                } message: {
                    if program.isWaitlistProgram {
                        Text("You have been added to the waitlist for \(program.name). A confirmation email has been sent.")
                    } else {
                        Text("You have successfully registered for \(program.name). A confirmation email has been sent.")
                    }
                }
                .alert("Success!", isPresented: $showSuccessAlert) {
                    Button("OK") {
                        presentationMode.wrappedValue.dismiss()
                    }
                } message: {
                    Text("Registration successful! Check your email for confirmation.")
                }
                .alert("Error", isPresented: .constant(viewModel.errorMessage != nil), actions: {
                    Button("OK") { viewModel.errorMessage = nil }
                    Button("Retry") {
                        Task {
                            await viewModel.loadData(for: program.id)
                        }
                    }
                }, message: {
                    Text(viewModel.errorMessage ?? "An unknown error occurred.")
                })
                .alert("Payment Error", isPresented: $viewModel.showPaymentError) {
                    Button("OK", role: .cancel) {
                        viewModel.resetPaymentState()
                    }
                    if !viewModel.paymentErrorMessage.contains("contact support") {
                        Button("Retry") {
                            viewModel.resetPaymentState()
                            viewModel.initiatePayment(
                                for: program,
                                event: event,
                                memberName: memberNameText,
                                email: emailAddressText,
                                phone: phoneText
                            )
                        }
                    }
                } message: {
                    Text(viewModel.paymentErrorMessage)
                }
                .alert("Payment Successful!", isPresented: $viewModel.showPurchaseSuccess) {
                    Button("OK") {
                        viewModel.cleanup()
                        presentationMode.wrappedValue.dismiss()
                    }
                } message: {
                    Text("Your payment has been processed and registration is complete!")
                }
                .sheet(item: $viewModel.approvalURL, onDismiss: {
                    // Handle early dismissal of PayPal sheet
                    if !viewModel.showPurchaseSuccess {
                        viewModel.resetPaymentState()
                    }
                }) { url in
                    PayPalView(
                        approvalURL: url,
                        showPaymentError: $viewModel.showPaymentError,
                        paymentErrorMessage: $viewModel.paymentErrorMessage,
                        showPurchaseSuccess: $viewModel.showPurchaseSuccess,
                        paymentConfirmationData: $viewModel.paymentConfirmationData,
                        comments: "\(program.name) Registration",
                        successMessage: "Registration payment completed successfully!"
                    )
                }
                .confirmationDialog(
                    "Confirm Payment",
                    isPresented: $showPaymentConfirmation,
                    presenting: pendingPaymentInfo
                ) { info in
                    let isMember = DatabaseManager.shared.currentUser?.isMember ?? false
                    let totalAmount = viewModel.totalChargeAmount(for: program, isMember: isMember)
                    Button("Pay \(formattedCurrency(totalAmount)) & Continue") {
                        viewModel.initiatePayment(
                            for: program,
                            event: event,
                            memberName: info.name,
                            email: info.email,
                            phone: info.phone
                        )
                        pendingPaymentInfo = nil
                    }
                    Button("Cancel", role: .cancel) {
                        pendingPaymentInfo = nil
                    }
                } message: { _ in
                    let isMember = DatabaseManager.shared.currentUser?.isMember ?? false
                    let totalAmount = viewModel.totalChargeAmount(for: program, isMember: isMember)
                    let count = viewModel.totalParticipantCount
                    Text("You are registering \(count) participant\(count == 1 ? "" : "s") for \(program.name). Total charge: \(formattedCurrency(totalAmount)). Continue to PayPal?")
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .didReceiveJWT)) { _ in
            Task {
                await viewModel.loadData(for: program.id)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .didSessionExpire)) { _ in
            viewModel.cleanup()
        }
        .onDisappear {
            viewModel.cleanup()
        }
    }
    
    private func loadUserInfo() {
        if let user = DatabaseManager.shared.currentUser {
            memberNameText = user.name
            emailAddressText = user.email
            phoneText = user.phone
        }
    }
    
    private func formattedCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount)) ?? String(format: "$%.2f", amount)
    }
}



struct TermsDisclosureView: View {
    let instructionsHTML: String?
    let refundPolicyHTML: String?
    let penaltyDetails: PenaltyDetails?

    @State private var isExpanded = false

    private let defaultInstructions = [
        "Please provide the requested participant details before submitting your registration.",
        "Registration fees are due at the time of submission. Pay by PayPal or credit card via PayPal guest checkout.",
        "Verify that your PayPal login (or guest checkout) works prior to starting the registration.",
        "Membership status will be validated at the event check-in.",
        "NEMA reserves the right to request a birth certificate to verify participant ages.",
        "Check your email SPAM folder if you do not see a confirmation email.",
        "Food Allergy Disclaimer: Meals or snacks may contain allergens. Consume at your own risk.",
        "Firecrackers Disclaimer: Certain events may include fireworks. NEMA is not responsible for injuries or damages."
    ]

    private let defaultRefunds = [
        "A full refund will be issued only if NEMA cancels the event.",
        "Withdrawing before the registration deadline incurs the program-specific penalty shown below.",
        "Withdrawing after the registration deadline forfeits 100% of the fees."
    ]

    var body: some View {
        Section {
            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    ProgramPoliciesCard(
                        instructionsHTML: instructionsHTML,
                        refundPolicyHTML: refundPolicyHTML,
                        penaltyDetails: penaltyDetails,
                        defaultInstructionBullets: defaultInstructions,
                        defaultRefundBullets: defaultRefunds
                    )
                }
                .transition(.opacity)
            }
        } header: {
            Button(action: { withAnimation { isExpanded.toggle() } }) {
                HStack {
                    Text("View Rules & Policies")
                        .font(.headline)
                        .foregroundColor(.orange)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.orange)
                }
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
}
struct ProgramPaymentSummaryView: View {
    let participantCount: Int
    let perParticipantAmount: Double
    let totalAmount: Double
    let programName: String
    
    private var currencyFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter
    }
    
    private var formattedPerParticipant: String {
        guard perParticipantAmount > 0 else { return "Free" }
        return currencyFormatter.string(from: NSNumber(value: perParticipantAmount)) ?? String(format: "$%.2f", perParticipantAmount)
    }
    
    private var formattedTotal: String {
        guard totalAmount > 0 else { return "Select participants" }
        return currencyFormatter.string(from: NSNumber(value: totalAmount)) ?? String(format: "$%.2f", totalAmount)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Participants")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Text(participantCount > 0 ? "\(participantCount)" : "–")
                    .font(.headline)
            }
            Divider()
            HStack {
                Text("Per Participant")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Text(formattedPerParticipant)
                    .font(.headline)
                    .foregroundColor(.primary)
            }
            Divider()
            HStack {
                Text("Total Due")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Text(formattedTotal)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(totalAmount > 0 ? .primary : .secondary)
            }
            Text("Amount is calculated for \(participantCount > 0 ? "\(participantCount)" : "no") participant(s) selected for \(programName).")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

struct ProgramPoliciesCard: View {
    let instructionsHTML: String?
    let refundPolicyHTML: String?
    let penaltyDetails: PenaltyDetails?
    let defaultInstructionBullets: [String]
    let defaultRefundBullets: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            instructionsSection
            Divider()
            refundSection
            if let penaltyDetails, (penaltyDetails.showPenalty ?? false) {
                Divider()
                penaltySection(details: penaltyDetails)
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
    }

    @ViewBuilder
    private var instructionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Instructions")
                .font(.headline)
                .foregroundColor(.orange)
            if let instructionsHTML, !instructionsHTML.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ProgramHTMLText(html: instructionsHTML)
            } else {
                bulletList(defaultInstructionBullets)
            }
        }
    }

    @ViewBuilder
    private var refundSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Refund Policy")
                .font(.headline)
                .foregroundColor(.orange)
            if let refundPolicyHTML, !refundPolicyHTML.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ProgramHTMLText(html: refundPolicyHTML)
            } else {
                bulletList(defaultRefundBullets)
            }
        }
    }

    private func penaltySection(details: PenaltyDetails) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Withdrawal Penalty")
                .font(.headline)
                .foregroundColor(.orange)
            if let regCloseDate = details.regCloseDate {
                Text("Registration Deadline: \(regCloseDate)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            if let penaltyText = details.withdrawalPenaltyText {
                Text(penaltyText)
                    .font(.subheadline)
                    .foregroundColor(Color(.secondaryLabel))
            } else if details.penaltyType == "no_refund" {
                Text("No refunds available after registration closes.")
                    .font(.subheadline)
                    .foregroundColor(Color(.secondaryLabel))
            }
        }
    }

    private func bulletList(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(items, id: \.self) { item in
                Text("• \(item)")
                    .font(.subheadline)
                    .foregroundColor(Color(.secondaryLabel))
            }
        }
    }
}

struct ProgramHTMLText: View {
    let html: String

    var body: some View {
        Text(createAttributedString())
    }

    private func createAttributedString() -> AttributedString {
        let styledHTML = """
        <style>
            body {
                font-family: -apple-system, sans-serif;
                font-size: \(UIFont.preferredFont(forTextStyle: .body).pointSize)px;
                color: \(UIColor.label.toHex());
            }
        </style>
        \(html)
        """

        guard let data = styledHTML.data(using: .utf8),
              let nsAttributedString = try? NSAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue
                ],
                documentAttributes: nil
              ) else {
            return AttributedString()
        }

        return AttributedString(nsAttributedString)
    }
}


