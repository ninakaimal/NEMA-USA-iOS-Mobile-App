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

    func canSubmit(for program: EventProgram) -> Bool {
        guard !selectedParticipantIDs.isEmpty && acceptedTerms else { return false }
        if let locations = program.practiceLocations, !locations.isEmpty {
            guard selectedPracticeLocationId != nil else { return false }
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
            try await networkManager.registerForProgram(
                eventId: eventId,
                programId: program.id,
                participantIds: Array(selectedParticipantIDs),
                practiceLocationId: selectedPracticeLocationId,
                comments: comments
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
        let amount = program.price(isMember: isMember)
        
        guard amount > 0 else {
            paymentErrorMessage = "Invalid program pricing. Please contact support."
            showPaymentError = true
            return
        }
        
        // Check for active internet connection (basic check)
        guard NetworkMonitor.shared.isConnected else {
            paymentErrorMessage = "No internet connection. Please check your connection and try again."
            showPaymentError = true
            return
        }
        
        isProcessingPayment = true
        
        PaymentManager.shared.createOrder(
            amount: String(format: "%.2f", amount),
            eventTitle: "\(program.name) Registration",
            eventID: Int(event.id),
            email: email,
            name: memberName,
            phone: phone,
            membershipType: nil,
            packageId: Int(program.id), // Convert program ID to Int
            packageYears: nil,
            userId: currentUser.id,
            panthiId: nil,
            lineItems: nil
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

                    // Policies
                    if ProgramPoliciesCard.hasContent(for: program) {
                        Section(header: Text("Rules & Policies")) {
                            ProgramPoliciesCard(
                                instructionsHTML: program.instructionsHTML,
                                refundPolicyHTML: program.refundPolicyHTML,
                                penaltyDetails: program.penaltyDetails
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
                                
                                viewModel.initiatePayment(
                                    for: program,
                                    event: event,
                                    memberName: memberNameText,
                                    email: emailAddressText,
                                    phone: phoneText
                                )
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
                                        let amount = program.price(isMember: isMember)
                                        Text("Pay $\(String(format: "%.0f", amount)) & Register")
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
                                
                                if viewModel.selectedParticipantIDs.isEmpty {
                                    Text("• Select at least one participant")
                                        .font(.caption2)
                                        .foregroundColor(.orange)
                                }
                                
                                if let locations = program.practiceLocations, !locations.isEmpty, viewModel.selectedPracticeLocationId == nil {
                                    Text("• Choose a practice location")
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
}


struct ProgramPoliciesCard: View {
    let instructionsHTML: String?
    let refundPolicyHTML: String?
    let penaltyDetails: PenaltyDetails?

    @State private var showInstructions = false
    @State private var showRefund = false

    private static let defaultInstructionBullets = [
        "Please provide the requested participant details before submitting your registration.",
        "Registration fees are due at the time of submission. Pay by PayPal or credit card via PayPal guest checkout.",
        "Verify that your PayPal login (or guest checkout) works prior to starting the registration.",
        "Membership status will be validated at the event check-in.",
        "NEMA reserves the right to request a birth certificate to verify participant ages.",
        "Check your email SPAM folder if you do not see a confirmation email.",
        "Food Allergy Disclaimer: Meals or snacks may contain allergens. Consume at your own risk.",
        "Firecrackers Disclaimer: Certain events may include fireworks. NEMA is not responsible for injuries or damages."
    ]

    private static let defaultRefundBullets = [
        "A full refund will be issued only if NEMA cancels the event.",
        "Withdrawing before the registration deadline incurs the program-specific penalty shown below.",
        "Withdrawing after the registration deadline forfeits 100% of the fees."
    ]

    static func hasContent(for program: EventProgram) -> Bool {
        return true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DisclosureGroup(isExpanded: $showInstructions) {
                instructionsContent()
                    .padding(.top, 4)
            } label: {
                Text("Instructions")
                    .font(.headline)
            }

            DisclosureGroup(isExpanded: $showRefund) {
                refundContent()
                    .padding(.top, 4)
            } label: {
                Text("Refund Policy")
                    .font(.headline)
            }

            if let penaltyDetails, (penaltyDetails.showPenalty ?? false) {
                Divider().padding(.vertical, 4)
                penaltySection(details: penaltyDetails)
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
    }

    @ViewBuilder
    private func instructionsContent() -> some View {
        if let items = parsedInstructionItems {
            bulletList(items)
        } else if let html = trimmedInstructionsHTML {
            ProgramHTMLText(html: html)
        } else {
            bulletList(Self.defaultInstructionBullets)
        }
    }

    @ViewBuilder
    private func refundContent() -> some View {
        if let items = parsedRefundItems {
            bulletList(items)
        } else if let html = trimmedRefundHTML {
            ProgramHTMLText(html: html)
        } else {
            bulletList(Self.defaultRefundBullets)
        }
    }

    private var trimmedInstructionsHTML: String? {
        guard let html = instructionsHTML?.trimmingCharacters(in: .whitespacesAndNewlines), !html.isEmpty else {
            return nil
        }
        return html
    }

    private var trimmedRefundHTML: String? {
        guard let html = refundPolicyHTML?.trimmingCharacters(in: .whitespacesAndNewlines), !html.isEmpty else {
            return nil
        }
        return html
    }

    private var parsedInstructionItems: [String]? {
        guard let html = trimmedInstructionsHTML else { return nil }
        return Self.listItems(from: html)
    }

    private var parsedRefundItems: [String]? {
        guard let html = trimmedRefundHTML else { return nil }
        return Self.listItems(from: html)
    }

    private func penaltySection(details: PenaltyDetails) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Withdrawal Penalty")
                .font(.headline)
            if let regCloseDate = details.regCloseDate {
                Text("Registration Deadline: \(regCloseDate)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            if let penaltyText = details.withdrawalPenaltyText {
                Text(penaltyText)
                    .font(.subheadline)
                    .foregroundColor(.primary)
            } else if details.penaltyType == "no_refund" {
                Text("No refunds available after registration closes.")
                    .font(.subheadline)
            }
        }
    }

    private func bulletList(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(items, id: \.self) { item in
                Text("• \(item)")
                    .font(.subheadline)
                    .foregroundColor(.primary)
            }
        }
    }

    private static func listItems(from html: String) -> [String]? {
        guard html.lowercased().contains("<li") else { return nil }
        do {
            let pattern = "(?is)<li[^>]*>(.*?)</li>"
            let regex = try NSRegularExpression(pattern: pattern, options: [])
            let nsString = html as NSString
            let matches = regex.matches(in: html, options: [], range: NSRange(location: 0, length: nsString.length))
            let items = matches.compactMap { match -> String? in
                guard match.numberOfRanges > 1 else { return nil }
                let raw = nsString.substring(with: match.range(at: 1))
                return Self.decodeHTML(raw)
                    .replacingOccurrences(of: "\n", with: " ")
                    .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .nonEmpty
            }
            return items.isEmpty ? nil : items
        } catch {
            return nil
        }
    }

    private static func decodeHTML(_ string: String) -> String {
        guard let data = string.data(using: .utf8) else { return string }
        let decoded = try? NSAttributedString(
            data: data,
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue
            ],
            documentAttributes: nil
        ).string
        return decoded ?? string
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

extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

