//
//  GroupProgramRegistrationView.swift
//  NEMA USA
//
//  Created by Sajith Kaimal on 2/1/26.
//

import SwiftUI

struct ParticipantEntry: Identifiable, Hashable {
    let id = UUID()
    var name: String = ""
    var age: String = ""
}

@MainActor
final class GroupProgramRegistrationViewModel: ObservableObject {
    @Published var selectedCategoryId: Int? = nil
    @Published var participantCountText: String = ""
    @Published var participants: [ParticipantEntry] = []
    @Published var selectedPracticeLocationId: Int? = nil
    @Published var groupName: String = ""
    @Published var guru: String = ""
    @Published var contactName: String = ""
    @Published var contactEmail: String = ""
    @Published var contactPhone: String = ""
    @Published var comments: String = ""
    @Published var acceptedTerms: Bool = false

    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil

    @Published var isProcessingPayment: Bool = false
    @Published var showPaymentError: Bool = false
    @Published var paymentErrorMessage: String = ""
    @Published var showPurchaseSuccess: Bool = false
    @Published var approvalURL: URL? = nil
    @Published var paymentConfirmationData: PaymentConfirmationResponse? = nil
    @Published var registrationSuccess: Bool = false

    private let networkManager = NetworkManager.shared

    func setupDefaults(for program: EventProgram) {
        let minCount = program.resolvedMinTeamSize
        participantCountText = String(minCount)
        updateParticipantCount(to: minCount)
        if selectedCategoryId == nil {
            selectedCategoryId = program.categories.first?.id
        }
        if let user = DatabaseManager.shared.currentUser {
            contactName = user.name
            contactEmail = user.email
            contactPhone = user.phone
        }
    }

    func updateParticipantCount(to newCount: Int) {
        let count = max(0, newCount)
        var updated = Array(participants.prefix(count))
        if updated.count < count {
            let additions = Array(repeating: ParticipantEntry(), count: count - updated.count)
            updated.append(contentsOf: additions)
        }
        participants = updated
    }

    func parsedParticipantCount() -> Int? {
        Int(participantCountText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func canSubmit(for program: EventProgram) -> Bool {
        guard acceptedTerms else { return false }
        guard let selectedCategoryId = selectedCategoryId, program.categories.contains(where: { $0.id == selectedCategoryId }) else { return false }
        guard let count = parsedParticipantCount() else { return false }
        guard count >= program.resolvedMinTeamSize && count <= program.resolvedMaxTeamSize else { return false }
        guard participants.count == count else { return false }
        guard !participants.contains(where: { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { return false }

        if program.showAgeOption == true {
            guard !participants.contains(where: { $0.age.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { return false }
        }

        if program.showGroupNameOption == true {
            guard !groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        }

        if program.showGuruOption == true {
            guard !guru.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        }

        if !contactName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !contactEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }

        return false
    }

    func totalAmount(for program: EventProgram) -> Double {
        guard let count = parsedParticipantCount() else { return 0 }
        let isMember = DatabaseManager.shared.currentUser?.isMember ?? false
        let price = program.price(isMember: isMember)
        return price * Double(count)
    }

    func initiatePayment(for program: EventProgram, event: Event) {
        guard canSubmit(for: program) else {
            paymentErrorMessage = "Please complete all required fields and accept terms"
            showPaymentError = true
            return
        }

        guard let currentUser = DatabaseManager.shared.currentUser else {
            paymentErrorMessage = "User authentication required for payment. Please log out and log back in."
            showPaymentError = true
            return
        }

        let amount = totalAmount(for: program)
        guard amount > 0 else {
            paymentErrorMessage = "Invalid program pricing. Please contact support."
            showPaymentError = true
            return
        }

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
            email: contactEmail,
            name: contactName,
            phone: contactPhone,
            membershipType: nil,
            packageId: Int(program.id),
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
                        guard url.scheme == "https" else {
                            self.paymentErrorMessage = "Invalid payment URL received"
                            self.showPaymentError = true
                            return
                        }
                        self.approvalURL = url
                    } else {
                        self.paymentErrorMessage = "Payment setup failed - no payment URL received"
                        self.showPaymentError = true
                    }
                case .failure(let error):
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
                        case .parseError:
                            friendlyMessage += "Error processing payment response. Please contact support if this continues."
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

    func submitRegistration(eventId: String, program: EventProgram) async {
        guard let count = parsedParticipantCount() else { return }
        guard canSubmit(for: program) else { return }

        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }

        do {
            let names = participants.map { $0.name }
            let ages = participants.map { $0.age }

            guard let selectedCategoryId = selectedCategoryId else {
                throw NetworkError.serverError("Please select a category.")
            }

            try await networkManager.registerGroupProgram(
                eventId: eventId,
                programId: program.id,
                programCategoryId: selectedCategoryId,
                participantNames: names,
                participantAges: ages,
                groupName: groupName,
                guru: guru,
                practiceLocationId: selectedPracticeLocationId,
                contactName: contactName,
                contactEmail: contactEmail,
                contactPhone: contactPhone,
                comments: comments,
                participantCount: count
            )

            await MainActor.run {
                registrationSuccess = true
                isLoading = false
            }
        } catch {
            await MainActor.run {
                if let networkError = error as? NetworkError {
                    switch networkError {
                    case .serverError(let message):
                        if message.contains("401") || message.contains("unauthorized") {
                            self.errorMessage = "Session expired. Please log out and log back in."
                        } else {
                            self.errorMessage = "Registration failed: \(message)"
                        }
                    case .invalidResponse:
                        self.errorMessage = "Unable to connect to server. Please check your internet connection."
                    case .decodingError:
                        self.errorMessage = "Received invalid data from server. Please try again."
                    }
                } else {
                    self.errorMessage = "Registration failed: \(error.localizedDescription)"
                }
                registrationSuccess = false
                isLoading = false
            }
        }
    }

    func resetPaymentState() {
        isProcessingPayment = false
        approvalURL = nil
        paymentConfirmationData = nil
        showPaymentError = false
        paymentErrorMessage = ""
    }

    func cleanup() {
        resetPaymentState()
        isLoading = false
        errorMessage = nil
    }
}

struct GroupProgramRegistrationView: View {
    let event: Event
    let program: EventProgram

    @StateObject private var viewModel = GroupProgramRegistrationViewModel()
    @Environment(\.presentationMode) private var presentationMode

    @State private var hasAppeared = false
    @State private var showSuccessAlert = false
    @State private var didSubmitAfterPayment = false

    private var selectedCategory: ProgramCategory? {
        program.categories.first(where: { $0.id == viewModel.selectedCategoryId })
    }

    var body: some View {
        NavigationView {
            if DatabaseManager.shared.jwtApiToken == nil {
                LoginView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Form {
                    Section(header: Text("Select Category")) {
                        ForEach(program.categories) { category in
                            HStack {
                                Image(systemName: viewModel.selectedCategoryId == category.id ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(viewModel.selectedCategoryId == category.id ? .orange : .gray)
                                VStack(alignment: .leading) {
                                    Text(category.name)
                                    if let priceText = priceLabelText() {
                                        Text(priceText)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                Spacer()
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                viewModel.selectedCategoryId = category.id
                            }
                        }
                    }

                    if program.showGroupNameOption == true {
                        Section(header: Text("Group Name")) {
                            TextField("Group Name", text: $viewModel.groupName)
                                .textFieldStyle(.roundedBorder)
                        }
                    }

                    if program.showGuruOption == true {
                        Section(header: Text("Guru/Choreographer")) {
                            TextField("Guru/Choreographer", text: $viewModel.guru)
                                .textFieldStyle(.roundedBorder)
                        }
                    }

                    if let locations = program.practiceLocations, !locations.isEmpty {
                        Section(header: Text("Select Practice Location")) {
                            Picker("Practice Location", selection: $viewModel.selectedPracticeLocationId) {
                                Text("Select a location").tag(nil as Int?)
                                ForEach(locations) { location in
                                    Text(location.location).tag(location.id as Int?)
                                }
                            }
                            .pickerStyle(MenuPickerStyle())
                        }
                    }

                    Section(header: Text("Number of Participants (Min \(program.resolvedMinTeamSize) / Max \(program.resolvedMaxTeamSize))")) {
                        HStack {
                            TextField("Count", text: $viewModel.participantCountText)
                                .keyboardType(.numberPad)
                                .textFieldStyle(.roundedBorder)
                            Button("Enter") {
                                let count = viewModel.parsedParticipantCount() ?? program.resolvedMinTeamSize
                                viewModel.updateParticipantCount(to: count)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)
                        }
                        if let count = viewModel.parsedParticipantCount(),
                           (count < program.resolvedMinTeamSize || count > program.resolvedMaxTeamSize) {
                            Text("Minimum: \(program.resolvedMinTeamSize) & Maximum: \(program.resolvedMaxTeamSize) team members allowed.")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }

                    Section(header: Text("Participants")) {
                        if viewModel.participants.isEmpty {
                            Text("Enter participant count to continue.")
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(Array(viewModel.participants.enumerated()), id: \..element.id) { index, _ in
                                VStack(alignment: .leading, spacing: 8) {
                                    TextField("Participant \(index + 1) Name", text: $viewModel.participants[index].name)
                                        .textFieldStyle(.roundedBorder)
                                    if program.showAgeOption == true {
                                        TextField("Age", text: $viewModel.participants[index].age)
                                            .keyboardType(.numberPad)
                                            .textFieldStyle(.roundedBorder)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }

                    Section(header: Text("Contact Person")) {
                        TextField("Contact Person Name", text: $viewModel.contactName)
                            .textFieldStyle(.roundedBorder)
                        TextField("Contact Person Phone", text: $viewModel.contactPhone)
                            .keyboardType(.phonePad)
                            .textFieldStyle(.roundedBorder)
                        TextField("Contact Person Email", text: $viewModel.contactEmail)
                            .keyboardType(.emailAddress)
                            .textFieldStyle(.roundedBorder)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                    }

                    Section(header: Text("Comments (Optional)")) {
                        TextEditor(text: $viewModel.comments)
                            .frame(height: 80)
                    }

                    if program.requiresPayment {
                        Section {
                            HStack {
                                Text("Amount")
                                Spacer()
                                Text("$\(String(format: "%.0f", viewModel.totalAmount(for: program)))")
                                    .font(.headline)
                                    .foregroundColor(.orange)
                            }
                        }
                    }

                    Section {
                        Toggle("I accept rules, guidelines and waiver for this program", isOn: $viewModel.acceptedTerms)
                    }

                    Section {
                        Button(action: {
                            if program.requiresPayment {
                                viewModel.initiatePayment(for: program, event: event)
                            } else {
                                Task { await viewModel.submitRegistration(eventId: event.id, program: program) }
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
                                    Text(program.isWaitlistProgram ? "Join Waitlist" : "Register")
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

                        if !viewModel.canSubmit(for: program) && !viewModel.isLoading {
                            validationHints
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
                        viewModel.setupDefaults(for: program)
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
                .alert("Payment Successful!", isPresented: $viewModel.showPurchaseSuccess) {
                    Button("OK") {
                        presentationMode.wrappedValue.dismiss()
                    }
                } message: {
                    Text("Your payment has been processed and registration is complete!")
                }
                .alert("Payment Error", isPresented: $viewModel.showPaymentError) {
                    Button("OK", role: .cancel) {
                        viewModel.resetPaymentState()
                    }
                } message: {
                    Text(viewModel.paymentErrorMessage)
                }
                .alert("Error", isPresented: .constant(viewModel.errorMessage != nil), actions: {
                    Button("OK") { viewModel.errorMessage = nil }
                }, message: {
                    Text(viewModel.errorMessage ?? "An unknown error occurred.")
                })
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
                .onChange(of: viewModel.showPurchaseSuccess) { success in
                    guard success, !didSubmitAfterPayment else { return }
                    didSubmitAfterPayment = true
                    Task { await viewModel.submitRegistration(eventId: event.id, program: program) }
                }
            }
        }
    }

    private var validationHints: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("To register, please:")
                .font(.caption)
                .foregroundColor(.secondary)

            if viewModel.selectedCategoryId == nil {
                Text("• Select a category")
                    .font(.caption2)
                    .foregroundColor(.orange)
            }

            if let count = viewModel.parsedParticipantCount(),
               (count < program.resolvedMinTeamSize || count > program.resolvedMaxTeamSize) {
                Text("• Enter a participant count within min/max range")
                    .font(.caption2)
                    .foregroundColor(.orange)
            }

            if viewModel.participants.contains(where: { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                Text("• Provide all participant names")
                    .font(.caption2)
                    .foregroundColor(.orange)
            }

            if program.showAgeOption == true,
               viewModel.participants.contains(where: { $0.age.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                Text("• Provide all participant ages")
                    .font(.caption2)
                    .foregroundColor(.orange)
            }

            if program.showGroupNameOption == true,
               viewModel.groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("• Enter a group name")
                    .font(.caption2)
                    .foregroundColor(.orange)
            }

            if program.showGuruOption == true,
               viewModel.guru.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("• Enter a guru/choreographer")
                    .font(.caption2)
                    .foregroundColor(.orange)
            }

            if viewModel.contactName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.contactEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("• Provide contact name and email")
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

    private func priceLabelText() -> String? {
        let isMember = DatabaseManager.shared.currentUser?.isMember ?? false
        let price = program.price(isMember: isMember)
        if price > 0 {
            return "$\(String(format: "%.0f", price)) each"
        }
        return nil
    }
}

