//  ProgramRegistrationView.swift
//  NEMA USA
//  Created by Arjun on 6/14/25.
//

import SwiftUI

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

    private let networkManager = NetworkManager.shared

    func canSubmit(for program: EventProgram) -> Bool {
        guard !selectedParticipantIDs.isEmpty && acceptedTerms else { return false }
        if let locations = program.practiceLocations, !locations.isEmpty {
            guard selectedPracticeLocationId != nil else { return false }
        }
        
        return true
    }

    func loadData(for programId: String) async {
        isLoading = true
        errorMessage = nil
        do {
            let fetchedParticipants = try await networkManager.getEligibleParticipants(forProgramId: programId)
            self.eligibleParticipants = fetchedParticipants
        } catch {
            errorMessage = "Failed to load participants. Please try again. \n(\(error.localizedDescription))"
        }
        isLoading = false
    }

    func submitRegistration(for eventId: String, program: EventProgram) async {
        guard canSubmit(for: program) else { return }
        
        // Check if practice location is required but not selected
        if let locations = program.practiceLocations, !locations.isEmpty, selectedPracticeLocationId == nil {
            errorMessage = "Please select a practice location"
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        do {
            try await networkManager.registerForProgram(
                eventId: eventId,
                programId: program.id,
                participantIds: Array(selectedParticipantIDs),
                practiceLocationId: selectedPracticeLocationId,
                comments: comments
            )
            registrationSuccess = true
        } catch {
            errorMessage = "Registration failed. Please try again. \n(\(error.localizedDescription))"
            registrationSuccess = false
        }
        isLoading = false
    }
}


// MARK: - Main View
struct ProgramRegistrationView: View {
    let event: Event
    let program: EventProgram
    
    @StateObject private var viewModel = ProgramRegistrationViewModel()
    @Environment(\.presentationMode) private var presentationMode
    
    var body: some View {
        NavigationView {
            Form {
                // Section 1: Participant Selection
                Section(header: Text("Select Participants")) {
                    if viewModel.isLoading {
                        ProgressView()
                    } else if let errorMsg = viewModel.errorMessage {
                        Text(errorMsg).foregroundColor(.red)
                    } else if viewModel.eligibleParticipants.isEmpty {
                        Text("No eligible family members found for this program's age requirements.")
                            .foregroundColor(.secondary)
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
                
                // Section 2: Practice Location Selection (if applicable)
                if let locations = program.practiceLocations, !locations.isEmpty {
                    Section(header: HStack {
                        Text("Select Practice Location")
                        Text("*").foregroundColor(.red) // Required indicator
                    }) {
                        Picker("Practice Location", selection: $viewModel.selectedPracticeLocationId) {
                            Text("Select a location").tag(nil as Int?)
                            ForEach(locations) { location in
                                Text(location.location).tag(location.id as Int?)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                        // Show validation error if not selected
                        if viewModel.selectedPracticeLocationId == nil && viewModel.acceptedTerms && !viewModel.selectedParticipantIDs.isEmpty {
                            Text("Practice location is required for this program")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                }
                
                // Section 3: Comments
                Section(header: Text("Comments (Optional)")) {
                    TextEditor(text: $viewModel.comments)
                        .frame(height: 80)
                }
                
                // Section 4: Terms
                Section {
                    Toggle("I accept rules, guidelines and waiver for this program", isOn: $viewModel.acceptedTerms)
                }
                
                // Section 5: Submit Button
                Section {
                    Button(action: {
                        Task { await viewModel.submitRegistration(for: event.id, program: program) }
                    }) {
                        HStack {
                            Spacer()
                            if viewModel.isLoading {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text(program.registrationStatus == "Join Waitlist" ? "Join Waitlist" : "Register")
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
                    .disabled(!viewModel.canSubmit(for: program) || viewModel.isLoading)
                    
                    // Show helpful message when button is disabled
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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { presentationMode.wrappedValue.dismiss() }
                        .foregroundColor(.white)
                }
            }
            .task {
                await viewModel.loadData(for: program.id)
            }
            .alert("Success", isPresented: $viewModel.registrationSuccess) {
                Button("OK", role: .cancel) { presentationMode.wrappedValue.dismiss() }
            } message: {
                Text("You have successfully registered for \(program.name). A confirmation email has been sent.")
            }
            .alert("Error", isPresented: .constant(viewModel.errorMessage != nil), actions: {
                Button("OK") { viewModel.errorMessage = nil }
            }, message: {
                Text(viewModel.errorMessage ?? "An unknown error occurred.")
            })
        }
    }
} // end of file
