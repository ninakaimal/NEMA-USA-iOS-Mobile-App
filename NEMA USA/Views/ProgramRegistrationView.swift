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
    @Published var comments: String = ""
    @Published var acceptedTerms = false
    
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var registrationSuccess = false

    private let networkManager = NetworkManager.shared

    var canSubmit: Bool {
        !selectedParticipantIDs.isEmpty && acceptedTerms
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
        guard canSubmit else { return }
        
        isLoading = true
        errorMessage = nil
        
        do {
            try await networkManager.registerForProgram(
                eventId: eventId,
                programId: program.id,
                participantIds: Array(selectedParticipantIDs),
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
                
                // Section 2: Comments
                Section(header: Text("Comments (Optional)")) {
                    TextEditor(text: $viewModel.comments)
                        .frame(height: 80)
                }
                
                // Section 3: Terms
                Section {
                    Toggle("I accept rules, guidelines and waiver for this program", isOn: $viewModel.acceptedTerms)
                }
                
                // --- UX CHANGE: Section 4: Submit Button ---
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
                    // Use a ternary operator to change color based on disabled state
                    .background(viewModel.canSubmit ? Color.orange : Color.gray)
                    .cornerRadius(10)
                    .disabled(!viewModel.canSubmit || viewModel.isLoading)
                    // This modifier makes the button fill the full width of the form
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                }
            }
            .navigationTitle(program.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // The confirmation button has been moved, only the Cancel button remains.
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
