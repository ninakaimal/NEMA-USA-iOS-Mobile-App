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
    
    @Published var selectedCategory: ProgramCategory?
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
    
    private let networkManager = NetworkManager.shared
    
    init(event: Event, program: EventProgram) {
        self.event = event
        self.program = program
        let initialCount = program.minTeamSizeValue
        self.participantCount = max(initialCount, 1)
        self.participantCountText = String(max(initialCount, 1))
        self.participantEntries = Array(repeating: GroupParticipantEntry(), count: max(initialCount, 1))
        self.selectedCategory = program.categories.first
        if let user = DatabaseManager.shared.currentUser {
            self.contactName = user.name
            self.contactEmail = user.email
            self.contactPhone = user.phone
        }
    }
    
    var minParticipants: Int { program.minTeamSizeValue }
    var maxParticipants: Int { program.maxTeamSizeValue }
    var showAgeFields: Bool { program.showAgeOption ?? true }
    var requiresGroupName: Bool { program.showGroupNameOption ?? false }
    var requiresGuru: Bool { program.showGuruOption ?? false }
    var requiresPracticeLocation: Bool { (program.practiceLocations?.isEmpty == false) }
    var isMember: Bool { DatabaseManager.shared.currentUser?.isMember ?? false }
    var perParticipantAmount: Double { program.price(isMember: isMember) }
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
        if program.requiresPayment && contactPhone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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
        return validationIssues().isEmpty && !isSubmitting
    }
    
    func submit() async {
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
        let trimmedNames = participantEntries.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }
        let agesPayload: [Any]
        if showAgeFields {
            agesPayload = participantEntries.map { entry in
                let trimmed = entry.ageText.trimmingCharacters(in: .whitespacesAndNewlines)
                return Int(trimmed) ?? NSNull()
            }
        } else {
            agesPayload = []
        }
        do {
            let response = try await networkManager.registerGroupProgram(
                programId: program.id,
                categoryId: category.id,
                participantNames: trimmedNames,
                participantAges: agesPayload,
                groupName: requiresGroupName ? groupName.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
                guruName: requiresGuru ? guruName.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
                practiceLocationId: selectedPracticeLocationId,
                contactName: contactName.trimmingCharacters(in: .whitespacesAndNewlines),
                contactEmail: contactEmail.trimmingCharacters(in: .whitespacesAndNewlines),
                contactPhone: contactPhone.trimmingCharacters(in: .whitespacesAndNewlines),
                comments: comments.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            successMessage = response.success ?? "Registration submitted successfully."
            showSuccessAlert = true
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
    
    init(event: Event, program: EventProgram) {
        self.event = event
        self.program = program
        _viewModel = StateObject(wrappedValue: GroupProgramRegistrationViewModel(event: event, program: program))
    }
    
    var body: some View {
        NavigationView {
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
                if program.requiresPayment {
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
                    presentationMode.wrappedValue.dismiss()
                }
            } message: {
                Text(viewModel.successMessage ?? "Registration submitted successfully.")
            }
            .alert("Error", isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("OK") {}
            } message: {
                Text(viewModel.errorMessage ?? "An error occurred.")
            }
        }
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
                Text("Select a category").tag(Optional<ProgramCategory>.none)
                ForEach(program.categories, id: \.id) { category in
                    Text(category.name).tag(Optional(category))
                }
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
            ForEach(viewModel.participantEntries.indices, id: \ .self) { index in
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
        if let locations = program.practiceLocations, !locations.isEmpty {
            Section(header: Text("Select Practice Location")) {
                Picker("Practice Location", selection: $viewModel.selectedPracticeLocationId) {
                    Text("Select a location").tag(Optional<Int>.none)
                    ForEach(locations) { location in
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
                Task { await viewModel.submit() }
            }) {
                HStack {
                    Spacer()
                    if viewModel.isSubmitting {
                        ProgressView().tint(.white)
                    }
                    Text(viewModel.isSubmitting ? "Submitting..." : "Submit Registration")
                        .fontWeight(.semibold)
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

