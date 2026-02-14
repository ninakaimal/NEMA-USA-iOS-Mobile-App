//  GroupProgramRegistrationView.swift
//  NEMA USA
//
//  Created by Kendra on 02/12/26.
//

import SwiftUI

struct GroupParticipantEntry: Identifiable, Equatable {
    let id = UUID()
    var name: String = ""
    var ageText: String = ""
}

@MainActor
final class GroupProgramRegistrationViewModel: ObservableObject {
    let event: Event
    let program: EventProgram
    
    @Published var registrationInfo: GroupRegistrationInfo?
    @Published var selectedCategory: GroupRegistrationCategory?
    @Published var categories: [GroupRegistrationCategory] = []
    @Published var participantEntries: [GroupParticipantEntry]
    @Published var participantCount: Int
    @Published var participantCountText: String
    @Published var groupName: String = ""
    @Published var guruName: String = ""
    @Published var comments: String = ""
    @Published var selectedPracticeLocationId: Int?
    @Published var contactName: String = ""
    @Published var contactEmail: String = ""
    @Published var contactPhone: String = ""
    @Published var acceptedTerms: Bool = false
    @Published var isSubmitting: Bool = false
    @Published var errorMessage: String?
    @Published var successMessage: String?
    @Published var showSuccessAlert: Bool = false
    @Published var isLoadingInfo: Bool = false
    
    // Payment state mirrors ProgramRegistrationViewModel
    @Published var isProcessingPayment: Bool = false
    @Published var paymentErrorMessage: String = ""
    @Published var showPaymentError: Bool = false
    @Published var showPurchaseSuccess: Bool = false
    @Published var approvalURL: URL? = nil
    @Published var paymentConfirmationData: PaymentConfirmationResponse? = nil
    
    private let networkManager = NetworkManager.shared
    
    init(event: Event, program: EventProgram) {
        self.event = event
        self.program = program
        let initialCount = program.minTeamSizeValue
        self.participantCount = max(initialCount, 1)
        self.participantCountText = String(max(initialCount, 1))
        self.participantEntries = Array(repeating: GroupParticipantEntry(), count: max(initialCount, 1))
        self.selectedCategory = nil
        if let user = DatabaseManager.shared.currentUser {
            self.contactName = user.name
            self.contactEmail = user.email
            self.contactPhone = user.phone
        }
    }
    
    var minParticipants: Int { registrationInfo?.minTeamSize ?? program.minTeamSizeValue }
    var maxParticipants: Int { registrationInfo?.maxTeamSize ?? program.maxTeamSizeValue }
    var showAgeFields: Bool { registrationInfo?.showAgeOption ?? program.showAgeOption ?? true }
    var requiresGroupName: Bool { registrationInfo?.showGroupNameOption ?? program.showGroupNameOption ?? false }
    var requiresGuru: Bool { registrationInfo?.showGuruOption ?? program.showGuruOption ?? false }
    var requiresPracticeLocation: Bool {
        if let info = registrationInfo {
            return info.practiceLocations?.isEmpty == false
        }
        return program.practiceLocations?.isEmpty == false
    }
    var isMember: Bool { DatabaseManager.shared.currentUser?.isMember ?? false }
    var perParticipantAmount: Double {
        if program.isWaitlistProgram { return 0 }
        if let info = registrationInfo {
            let memberFee = info.paidMemberFee ?? info.othersFee ?? 0
            let nonMemberFee = info.othersFee ?? info.paidMemberFee ?? 0
            return isMember ? memberFee : nonMemberFee
        }
        return program.price(isMember: isMember)
    }
    var totalAmount: Double { perParticipantAmount * Double(participantCount) }
    
    func applyParticipantCount() {
        let desired = Int(participantCountText) ?? minParticipants
        let clamped = min(max(desired, minParticipants), maxParticipants)
        updateParticipantCount(to: clamped)
    }
    
    func updateParticipantCount(to newValue: Int) {
        participantCount = newValue
        participantCountText = String(newValue)
        if participantEntries.count < newValue {
            let difference = newValue - participantEntries.count
            participantEntries.append(contentsOf: Array(repeating: GroupParticipantEntry(), count: difference))
        } else if participantEntries.count > newValue {
            participantEntries = Array(participantEntries.prefix(newValue))
        }
    }
    
    func loadRegistrationInfoIfNeeded() async {
        if registrationInfo != nil || isLoadingInfo { return }
        await loadRegistrationInfo()
    }
    
    private func loadRegistrationInfo() async {
        isLoadingInfo = true
        defer { isLoadingInfo = false }
        do {
            let info = try await networkManager.fetchGroupRegistrationInfo(programId: program.id)
            registrationInfo = info
            categories = info.categories
            selectedCategory = info.categories.first
            let initialCount = max(info.minTeamSize, 1)
            participantCount = initialCount
            participantCountText = String(initialCount)
            participantEntries = Array(repeating: GroupParticipantEntry(), count: initialCount)
            if info.practiceLocations?.isEmpty == false {
                if selectedPracticeLocationId == nil {
                    selectedPracticeLocationId = info.practiceLocations?.first?.id
                }
            } else {
                selectedPracticeLocationId = nil
            }
        } catch {
            errorMessage = "Failed to load registration info: \(error.localizedDescription)"
        }
    }
    

    private func initiateGroupPayment(participantId: Int, contactName: String, contactEmail: String, contactPhone: String) {
        let amountString = String(format: "%.2f", totalAmount)
        isProcessingPayment = true
        PaymentManager.shared.createOrder(
            amount: amountString,
            eventTitle: "\(program.name) Registration",
            eventID: nil,
            email: contactEmail,
            name: contactName,
            phone: contactPhone,
            membershipType: nil,
            packageId: nil,
            packageYears: nil,
            userId: nil,
            panthiId: nil,
            lineItems: nil,
            participantIds: nil,
            guestParticipant: nil,
            paymentTypeOverride: "group",
            groupParticipantId: participantId,
            groupProgramId: Int(program.id)
        ) { [weak self] result in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.isProcessingPayment = false
                switch result {
                case .success(let url):
                    if let approvalURL = url {
                        self.approvalURL = approvalURL
                    } else {
                        self.successMessage = "Registration submitted successfully."
                        self.showSuccessAlert = true
                    }
                case .failure(let error):
                    switch error {
                    case .serverError(let message):
                        self.paymentErrorMessage = message
                    default:
                        self.paymentErrorMessage = error.localizedDescription
                    }
                    self.showPaymentError = true
                }
            }
        }
    }

    func resetPaymentState() {
        approvalURL = nil
        paymentConfirmationData = nil
        isProcessingPayment = false
        paymentErrorMessage = ""
        showPaymentError = false
        showPurchaseSuccess = false
    }

    func cleanup() {
        resetPaymentState()
        isSubmitting = false
        showSuccessAlert = false
    }

    func ageRangeDescription() -> String? {
        guard let category = selectedCategory else { return nil }
        if let min = category.minAge, let max = category.maxAge {
            return "Ages \(min)-\(max)"
        } else if let min = category.minAge {
            return "Age ≥ \(min)"
        } else if let max = category.maxAge {
            return "Age ≤ \(max)"
        }
        return nil
    }
    
    func ageValidationError(for entry: GroupParticipantEntry) -> String? {
        guard showAgeFields else { return nil }
        guard let category = selectedCategory else { return "Select a category to validate age." }
        let trimmed = entry.ageText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Age required" }
        guard let value = Int(trimmed) else { return "Enter a valid age" }
        if let min = category.minAge, value < min { return "Minimum age is \(min)" }
        if let max = category.maxAge, value > max { return "Maximum age is \(max)" }
        return nil
    }
    
    func nameValidationError(for entry: GroupParticipantEntry) -> String? {
        return entry.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Name required" : nil
    }
    
    func validationIssues() -> [String] {
        var issues: [String] = []
        if selectedCategory == nil {
            issues.append("Select a category")
        }
        if requiresGroupName && groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append("Enter a group name")
        }
        if requiresGuru && guruName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append("Enter a guru/choreographer name")
        }
        if requiresPracticeLocation && selectedPracticeLocationId == nil {
            issues.append("Select a practice location")
        }
        if contactName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append("Contact name is required")
        }
        if contactEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append("Contact email is required")
        } else if !contactEmail.isValidEmail {
            issues.append("Enter a valid email address")
        }
        if perParticipantAmount > 0 && contactPhone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append("Contact phone is required")
        }
        for (index, entry) in participantEntries.enumerated() {
            if let nameError = nameValidationError(for: entry) {
                issues.append("Participant #\(index + 1): \(nameError)")
            }
            if let ageError = ageValidationError(for: entry) {
                issues.append("Participant #\(index + 1): \(ageError)")
            }
        }
        if !acceptedTerms {
            issues.append("Accept the rules and waiver")
        }
        return issues
    }
    
    var canSubmit: Bool {
        return validationIssues().isEmpty && !isSubmitting && !isProcessingPayment
    }
    
    func submit() async {
        guard registrationInfo != nil else {
            errorMessage = "Registration info is still loading. Please try again."
            return
        }
        guard let category = selectedCategory else {
            errorMessage = "Please select a category."
            return
        }
        guard validationIssues().isEmpty else {
            errorMessage = "Please fix the highlighted fields before continuing."
            return
        }
        isSubmitting = true
        errorMessage = nil
        let activeEntries = Array(participantEntries.prefix(participantCount))
        let trimmedNames = activeEntries.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }
        let agesPayload: [Int]? = showAgeFields ? activeEntries.map { entry in
            let trimmed = entry.ageText.trimmingCharacters(in: .whitespacesAndNewlines)
            return Int(trimmed) ?? 0
        } : nil
        do {
            let trimmedContactName = contactName.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedContactEmail = contactEmail.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedContactPhone = contactPhone.trimmingCharacters(in: .whitespacesAndNewlines)
            let response = try await networkManager.registerGroupProgram(
                programId: program.id,
                categoryId: category.id,
                participantNames: trimmedNames,
                participantAges: agesPayload,
                groupName: requiresGroupName ? groupName.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
                guruName: requiresGuru ? guruName.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
                practiceLocationId: selectedPracticeLocationId,
                contactName: trimmedContactName,
                contactEmail: trimmedContactEmail,
                contactPhone: trimmedContactPhone,
                comments: comments.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            if response.waitList == true || perParticipantAmount <= 0 {
                successMessage = response.success ?? "Registration submitted successfully."
                showSuccessAlert = true
            } else if let participantId = response.participantId {
                initiateGroupPayment(
                    participantId: participantId,
                    contactName: trimmedContactName,
                    contactEmail: trimmedContactEmail,
                    contactPhone: trimmedContactPhone
                )
            } else {
                errorMessage = "Unable to start payment: missing participant ID."
            }
        } catch let error as NetworkError {
            errorMessage = "Registration failed: \(error.localizedDescription)"
        } catch {
            errorMessage = "Registration failed: \(error.localizedDescription)"
        }
        isSubmitting = false
    }
}

struct GroupProgramRegistrationView: View {
    let event: Event
    let program: EventProgram
    @Environment(\.presentationMode) private var presentationMode
    @StateObject private var viewModel: GroupProgramRegistrationViewModel
    @State private var showPaymentConfirmation = false
    @State private var pendingPaymentInfo: (name: String, email: String, phone: String)? = nil
    
    init(event: Event, program: EventProgram) {
        self.event = event
        self.program = program
        _viewModel = StateObject(wrappedValue: GroupProgramRegistrationViewModel(event: event, program: program))
    }
    
    var body: some View {
        NavigationView {
            Group {
                if viewModel.isLoadingInfo && viewModel.registrationInfo == nil {
                    ProgressView("Loading registration info…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                } else {
                    Form {
                programHeaderSection
                categorySection
                participantCountSection
                participantsSection
                optionalDetailsSection
                contactSection
                practiceLocationSection
                commentsSection
                TermsDisclosureView(
                    instructionsHTML: program.instructionsHTML,
                    refundPolicyHTML: program.refundPolicyHTML,
                    penaltyDetails: program.penaltyDetails
                )
                Section {
                    Toggle("I accept rules, guidelines and waiver for this program", isOn: $viewModel.acceptedTerms)
                }
                if viewModel.perParticipantAmount > 0 {
                    Section(header: Text("Payment Summary")) {
                        ProgramPaymentSummaryView(
                            participantCount: viewModel.participantCount,
                            perParticipantAmount: viewModel.perParticipantAmount,
                            totalAmount: viewModel.totalAmount,
                            programName: program.name
                        )
                    }
                }
                submitSection
            }
                }
            }
            .navigationTitle(program.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { presentationMode.wrappedValue.dismiss() }
                        .foregroundColor(.white)
                }
            }
            .alert("Success", isPresented: Binding(
                get: { viewModel.showSuccessAlert },
                set: { viewModel.showSuccessAlert = $0 }
            )) {
                Button("OK") {
                    viewModel.cleanup()
                    presentationMode.wrappedValue.dismiss()
                }
            } message: {
                Text(viewModel.successMessage ?? "Registration submitted successfully.")
            }
            .alert("Payment Error", isPresented: $viewModel.showPaymentError) {
                Button("OK", role: .cancel) {
                    viewModel.resetPaymentState()
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
            .alert("Error", isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("OK") {}
            } message: {
                Text(viewModel.errorMessage ?? "An error occurred.")
            }
            .sheet(item: $viewModel.approvalURL, onDismiss: {
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
            ) { _ in
                Button("Pay \(formattedCurrency(viewModel.totalAmount)) & Continue") {
                    showPaymentConfirmation = false
                    Task { await viewModel.submit() }
                    pendingPaymentInfo = nil
                }
                Button("Cancel", role: .cancel) {
                    showPaymentConfirmation = false
                    pendingPaymentInfo = nil
                }
            } message: { _ in
                let count = viewModel.participantCount
                Text("You are registering \(count) participant\(count == 1 ? "" : "s") for \(program.name). Total charge: \(formattedCurrency(viewModel.totalAmount)). Continue to PayPal?")
            }
        }
        .task {
            await viewModel.loadRegistrationInfoIfNeeded()
        }
    }
    
    private var submitButtonTitle: String {
        if viewModel.perParticipantAmount > 0 {
            return "Pay \(formattedCurrency(viewModel.totalAmount)) & Register"
        } else {
            return "Submit Registration"
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

    private var programHeaderSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text(program.name)
                    .font(.headline)
                if program.requiresPayment {
                    Text(program.formattedPrice + " per participant")
                        .font(.caption)
                        .foregroundColor(.orange)
                } else {
                    Text("Free registration")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
        }
    }
    
    private var categorySection: some View {
        Section(header: Text("Select Category")) {
            Picker("Category", selection: $viewModel.selectedCategory) {
                Text("Select a category").tag(Optional<GroupRegistrationCategory>.none)
                ForEach(viewModel.categories) { category in
                    Text(category.name).tag(Optional(category))
                }
            }
            .disabled(viewModel.categories.isEmpty)
            if viewModel.categories.isEmpty {
                Text("No categories available for this program.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            if let rangeDescription = viewModel.ageRangeDescription() {
                Text(rangeDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var participantCountSection: some View {
        Section(header: Text("Enter Number of Participants (Min: \(viewModel.minParticipants) | Max: \(viewModel.maxParticipants))")) {
            HStack {
                TextField("Count", text: $viewModel.participantCountText)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                Button("Apply") {
                    viewModel.applyParticipantCount()
                }
                .buttonStyle(.borderedProminent)
            }
            Text("Currently adding \(viewModel.participantCount) participant(s)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private var participantsSection: some View {
        Section(header: Text("Participants")) {
            ForEach(viewModel.participantEntries.indices, id: \.self) { index in
                VStack(alignment: .leading, spacing: 8) {
                    Text("Participant #\(index + 1)")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    TextField("Participant Name", text: Binding(
                        get: { viewModel.participantEntries[index].name },
                        set: { viewModel.participantEntries[index].name = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.words)
                    .disableAutocorrection(true)
                    if let nameError = viewModel.nameValidationError(for: viewModel.participantEntries[index]) {
                        Text(nameError)
                            .font(.caption2)
                            .foregroundColor(.red)
                    }
                    if viewModel.showAgeFields {
                        TextField("Age", text: Binding(
                            get: { viewModel.participantEntries[index].ageText },
                            set: { viewModel.participantEntries[index].ageText = $0 }
                        ))
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                        if let ageError = viewModel.ageValidationError(for: viewModel.participantEntries[index]) {
                            Text(ageError)
                                .font(.caption2)
                                .foregroundColor(.red)
                        }
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var optionalDetailsSection: some View {
        Section(header: Text("Group Details")) {
            if viewModel.requiresGroupName {
                TextField("Group Name", text: $viewModel.groupName)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.words)
                    .disableAutocorrection(true)
            }
            if viewModel.requiresGuru {
                TextField("Guru / Choreographer", text: $viewModel.guruName)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.words)
                    .disableAutocorrection(true)
            }
        }
    }
    
    private var contactSection: some View {
        Section(header: Text("Contact Information")) {
            TextField("Contact Person", text: $viewModel.contactName)
                .textFieldStyle(.roundedBorder)
            TextField("Contact Email", text: $viewModel.contactEmail)
                .keyboardType(.emailAddress)
                .textFieldStyle(.roundedBorder)
            TextField("Contact Phone", text: $viewModel.contactPhone)
                .keyboardType(.phonePad)
                .textFieldStyle(.roundedBorder)
        }
    }
    
    @ViewBuilder
    private var practiceLocationSection: some View {
        if let locations = viewModel.registrationInfo?.practiceLocations, !locations.isEmpty {
            Section(header: Text("Select Practice Location")) {
                Picker("Practice Location", selection: $viewModel.selectedPracticeLocationId) {
                    Text("Select a location").tag(Optional<Int>.none)
                    ForEach(locations) { location in
                        Text(location.location).tag(Optional(location.id))
                    }
                }
            }
        } else if let legacyLocations = program.practiceLocations, !legacyLocations.isEmpty {
            Section(header: Text("Select Practice Location")) {
                Picker("Practice Location", selection: $viewModel.selectedPracticeLocationId) {
                    Text("Select a location").tag(Optional<Int>.none)
                    ForEach(legacyLocations) { location in
                        Text(location.location).tag(Optional(location.id))
                    }
                }
            }
        }
    }
    
    private var commentsSection: some View {
        Section(header: Text("Comments (Optional)")) {
            TextEditor(text: $viewModel.comments)
                .frame(height: 80)
        }
    }
    
    private var submitSection: some View {
        Section {
            Button(action: {
                if viewModel.perParticipantAmount > 0 {
                    pendingPaymentInfo = (
                        viewModel.contactName.trimmingCharacters(in: .whitespacesAndNewlines),
                        viewModel.contactEmail.trimmingCharacters(in: .whitespacesAndNewlines),
                        viewModel.contactPhone.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                    showPaymentConfirmation = true
                } else {
                    Task { await viewModel.submit() }
                }
            }) {
                HStack {
                    Spacer()
                    if viewModel.isSubmitting || viewModel.isProcessingPayment {
                        ProgressView().tint(.white)
                        Text(viewModel.isProcessingPayment ? "Opening PayPal..." : "Submitting...")
                            .fontWeight(.semibold)
                            .padding(.leading, 8)
                    } else {
                        Text(submitButtonTitle)
                            .fontWeight(.semibold)
                    }
                    Spacer()
                }
            }
            .disabled(!viewModel.canSubmit)
            .font(.headline)
            .foregroundColor(.white)
            .padding()
            .frame(maxWidth: .infinity)
            .background(viewModel.canSubmit ? Color.orange : Color.gray)
            .cornerRadius(10)
            if !viewModel.canSubmit {
                VStack(alignment: .leading, spacing: 4) {
                    Text("To continue, please:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    ForEach(viewModel.validationIssues(), id: \.self) { issue in
                        Text("• \(issue)")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }
            }
        }
    }
}

