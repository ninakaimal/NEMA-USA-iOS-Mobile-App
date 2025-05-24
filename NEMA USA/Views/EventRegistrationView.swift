//
//  EventRegistrationView.swift
//  NEMA USA
//  Created by Arjun on 4/20/25.
//  Added PayPal integration by Arjun on 4/22/25
//

import SwiftUI

// Allow URL in .sheet(item:)
extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

struct EventRegistrationView: View {
    let event: Event
    @Environment(\.presentationMode) private var presentationMode
    
    // MARK: - ViewModel
    @StateObject var viewModel = EventRegistrationViewModel()
    
    // MARK: – Login / Member state
    @State private var showLoginSheet          = false
    @State private var pendingPurchase         = false
    
    // User Info state variables (managed by the view for now)
    @State private var memberNameText   = ""
    @State private var emailAddressText = ""
    @State private var phoneText        = ""
    
    // MARK: – Ticket state
    @State private var acceptedTerms = false
    
    // MARK: – PayPal / Alerts
    // MARK: – PayPal / Alerts
    @State private var showPurchaseConfirmation = false
    @State private var showPurchaseSuccess      = false
    @State private var approvalURL: URL?        = nil
    @State private var showPaymentError    = false
    @State private var paymentErrorMessage = ""
    
    init(event: Event) {
        self.event = event
        // ... (your existing UINavigationBar appearance setup - this is fine for now) ...
        // Note: For modern SwiftUI, consider applying these modifiers directly to the NavigationView if possible.
        if #available(iOS 15.0, *) {
            let appearance = UINavigationBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor        = UIColor(Color.orange)
            appearance.titleTextAttributes    = [.foregroundColor: UIColor.white]
            appearance.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
            UINavigationBar.appearance().standardAppearance   = appearance
            UINavigationBar.appearance().scrollEdgeAppearance = appearance
        } else {
            UINavigationBar.appearance().barTintColor = .orange
        }
        UINavigationBar.appearance().tintColor = .white
        UIView.appearance(whenContainedInInstancesOf: [UIAlertController.self]).tintColor = UIColor(Color.orange) // For UIAlertController button color
    }
    
    var body: some View {
        content
            .navigationTitle("\(event.title) Tickets") // Set title here
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showLoginSheet, onDismiss: {
                loadMemberInfo() // Re-check user info after login attempt
                if pendingPurchase {
                    if DatabaseManager.shared.jwtApiToken != nil { // Check if login was successful
                        validateAndShowPurchaseConfirmation()
                    }
                    pendingPurchase = false
                }
            }) {
                LoginView() // Make sure LoginView updates DatabaseManager.shared states
            }
            .alert(
                "Confirm Purchase",
                isPresented: $showPurchaseConfirmation
            ) {
                Button("Cancel", role: .cancel) { }
                Button("Confirm") {
                    initiateMobilePayment()
                }
            } message: {
                Text(viewModel.purchaseSummary)
            }
        
        // MARK: – Show payment errors
            .alert(
                "Payment Information", // Changed title for clarity
                isPresented: $showPaymentError
            ) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(paymentErrorMessage)
            }
            .alert(
                "Purchase Successful!", // Updated title
                isPresented: $showPurchaseSuccess
            ) {
                Button("OK") { presentationMode.wrappedValue.dismiss() }
            } message: {
                Text("Check your email \(emailAddressText) for confirmation.")
            }
        
        // MARK: – PayPal approval sheet
            .sheet(item: $approvalURL) { url in
                PayPalView(
                    approvalURL:        url,
                    showPaymentError:   $showPaymentError,
                    paymentErrorMessage:$paymentErrorMessage,
                    showPurchaseSuccess:$showPurchaseSuccess,
                    comments:           "\(event.title) Tickets for \(memberNameText)", // More context
                    successMessage:     "Your tickets have been purchased successfully!"
                )
            }
            .onOpenURL { url in // PayPal redirect handling
                handlePayPalRedirect(url: url)
            }
            .task { // Use .task for async work on appear
                await viewModel.loadPrerequisites(for: event)
                loadMemberInfo() // Load/pre-fill user info once
            }
    }
    
    private var content: some View {
        ZStack(alignment: .top) {
            Color.orange
                .ignoresSafeArea(edges: .top)
                .frame(height: 56)
            
            ScrollView {
                VStack(spacing: 24) {
                    // Title now in navigationTitle, so this can be removed or kept if styled differently
                    // Text("\(event.title) Tickets")
                    //     .font(.title2).bold()
                    //     .padding(.horizontal)
                    //     .padding(.top, 16)
                    
                    infoCard
                    
                    if viewModel.isLoading {
                        ProgressView("Loading ticket options...")
                            .padding(.vertical, 40)
                    } else if let errorMsg = viewModel.errorMessage {
                        Text("Error loading options: \(errorMsg)")
                            .foregroundColor(.red)
                            .padding()
                    } else {
                        if event.usesPanthi ?? false { // Check the flag from the Event model
                            panthiSelectionCard
                        }
                        ticketSelectionCard // Dynamic ticket types
                    }
                    
                    termsCard
                    purchaseButton
                    
                    Spacer(minLength: 32)
                }
                .padding(.top, 16)
                .background(Color(.systemBackground))
            }
        }
    }
    
    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your Information")
                .font(.headline)
                .padding(.bottom, 4)
            
            Group {
                TextField("Name", text: $memberNameText).textFieldStyle(.roundedBorder)
                TextField("Email", text: $emailAddressText).keyboardType(.emailAddress).textFieldStyle(.roundedBorder)
                TextField("Phone", text: $phoneText).keyboardType(.phonePad).textFieldStyle(.roundedBorder)
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
        .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 3)
        .padding(.horizontal)
    }
    
    // MARK: - Dynamic Panthi Selection Card (NEW or Replaces Placeholder)
    @ViewBuilder
    private var panthiSelectionCard: some View {
        if !viewModel.availablePanthis.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Select Time Slot / Panthi")
                    .font(.headline)
                
                Picker("Select Slot", selection: $viewModel.selectedPanthiId) {
                    Text("Please select a slot").tag(nil as Int?) // For "no selection" state
                    ForEach(viewModel.availablePanthis) { panthi in
                        Text("\(panthi.name) (\(panthi.availableSlots) available)")
                            .tag(panthi.id as Int?) // Ensure tag matches optional Int
                            .disabled(panthi.availableSlots <= 0 && viewModel.selectedPanthiId != panthi.id)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .padding(.vertical, 5)
                .background(Color(.tertiarySystemBackground).opacity(0.7))
                .cornerRadius(8)
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
            .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 3)
            .padding(.horizontal)
        } else if event.usesPanthi ?? false { // Event uses panthis, but none loaded/available
            Text("No time slots are currently available for this event.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding()
                .frame(maxWidth: .infinity, alignment: .center)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
                .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 3)
                .padding(.horizontal)
        }
    }
    
    // MARK: - Dynamic Ticket Selection Card (Replaces old hardcoded ticketCard)
    private var ticketSelectionCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            if viewModel.availableTicketTypes.isEmpty && !viewModel.isLoading && viewModel.errorMessage == nil {
                Text("Ticket information will be available soon.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 20) // Add some padding if it's the only thing shown
            } else {
                ForEach(viewModel.availableTicketTypes) { ticketType in
                    let isUserActuallyMember = DatabaseManager.shared.currentUser?.isMember ?? false
                    if ticketType.isTicketTypeMemberExclusive == true && !isUserActuallyMember {
                        // Skip rendering this ticket type for non-members if it's exclusive
                    } else {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(ticketType.typeName):")
                                    .font(.headline)
                                Text("$\(String(format: "%.2f", viewModel.price(for: ticketType))) each")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Stepper(
                                "\(viewModel.ticketQuantities[ticketType.id] ?? 0)",
                                value: Binding(
                                    get: { viewModel.ticketQuantities[ticketType.id] ?? 0 },
                                    set: { newValue in viewModel.ticketQuantities[ticketType.id] = max(0, newValue) }
                                ),
                                in: 0...20 // Max quantity (adjust as needed)
                            )
                        }
                        // Add Divider only if it's not the last item
                        if viewModel.availableTicketTypes.last?.id != ticketType.id {
                            Divider()
                        }
                    }
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
        .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 3)
        .padding(.horizontal)
    }
    
    private var termsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Total cost:").font(.headline)
                Spacer()
                Text("$\(String(format: "%.2f", viewModel.totalAmount))").font(.headline)
            }
            DisclosureGroup("View Terms & Conditions") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("• Membership status validated at event.")
                    Text("• Verify PayPal login or use credit card (guest checkout).")
                    Text("• Age verification via birth certificate may be required.")
                    Text("• Check your spam folder if you don't see the confirmation email.")
                    Divider()
                    Text("**Waiver:** Fireworks used at event; NEMA not responsible for injuries or damages.")
                    Divider()
                    Text("**Refund Policy:** Non-refundable except if event is cancelled by NEMA.")
                }
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 8)
            }
            
            Toggle("I accept the terms & conditions", isOn: $acceptedTerms)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
        .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 3)
        .padding(.horizontal)
    }
    
    private var purchaseButton: some View {
        let canProceed = viewModel.canProceedToPurchase(
            acceptedTerms: acceptedTerms,
            eventUsesPanthi: event.usesPanthi ?? false,
            availablePanthisNonEmpty: !memberNameText.isEmpty && !emailAddressText.isEmpty && !phoneText.isEmpty && emailAddressText.isValidEmail
        )
        return Button("Purchase") {
            validateAndShowPurchaseConfirmation()
        }
        .disabled(!canProceed)
        .padding()
        .frame(maxWidth: .infinity)
        .background(canProceed ? Color.orange : Color.gray)
        .foregroundColor(.white)
        .cornerRadius(10)
        .padding(.horizontal)
    }
    
    private func loadMemberInfo() {
        if let user = DatabaseManager.shared.currentUser { //
            memberNameText = user.name
            emailAddressText = user.email
            phoneText = user.phone // UserProfile.phone is String?
            print("✅ [EventRegView] Loaded member info from DatabaseManager: Name: \(user.name)")
        } else {
            memberNameText = UserDefaults.standard.string(forKey: "memberName") ?? ""
            emailAddressText = UserDefaults.standard.string(forKey: "emailAddress") ?? ""
            phoneText = UserDefaults.standard.string(forKey: "phoneNumber") ?? ""
            print("ℹ️ [EventRegView] No current user, loaded from UserDefaults if available.")
        }
        // ßajith remove later
        print("Loaded member info from cache:",
              "Name:", memberNameText,
              "Email:", emailAddressText,
              "Phone:", phoneText)
    }
    private func validateAndShowPurchaseConfirmation() {
        guard DatabaseManager.shared.jwtApiToken != nil else {
            paymentErrorMessage = "Please log in to purchase tickets."
            showPaymentError = false
            pendingPurchase = true
            showLoginSheet = true
            return
        }
        
        guard !memberNameText.isEmpty else { paymentErrorMessage = "Full Name is required."; showPaymentError = true; return }
        guard !emailAddressText.isEmpty, emailAddressText.isValidEmail else { paymentErrorMessage = "Valid Email is required."; showPaymentError = true; return }
        guard !phoneText.isEmpty else { paymentErrorMessage = "Phone number is required."; showPaymentError = true; return }
        guard acceptedTerms else { paymentErrorMessage = "You must accept the terms & conditions."; showPaymentError = true; return }
        guard viewModel.totalAmount > 0 else { paymentErrorMessage = "Please select at least one ticket."; showPaymentError = true; return }
        
        if event.usesPanthi ?? false && !viewModel.availablePanthis.isEmpty && viewModel.selectedPanthiId == nil {
            paymentErrorMessage = "Please select a time slot/Panthi."
            showPaymentError = true; return
        }
        
        showPurchaseConfirmation = true
    }
    
    private func initiateMobilePayment() {
        UserDefaults.standard.set(event.id, forKey: "eventId") // Storing String event.id
        UserDefaults.standard.set(event.title, forKey: "item")
        
        guard let eventIDInt = Int(event.id) else { // Convert String event.id to Int
            paymentErrorMessage = "Invalid Event ID."
            showPaymentError = true
            return
        }
        
        PaymentManager.shared.createOrder( // This is the call that needs to match the signature
            amount: String(format: "%.2f", viewModel.totalAmount),
            eventTitle: event.title,
            eventID: eventIDInt,         // Your app's Event ID
            email: emailAddressText,
            name: memberNameText,
            phone: phoneText,
            // For event ticket purchases, membershipType, packageId, packageYears, userId are usually nil
            membershipType: nil,        // Explicitly nil for ticket purchases
            packageId: nil,             // Explicitly nil
            packageYears: nil,          // Explicitly nil
            userId: nil,                // Explicitly nil (unless you link ticket purchase to a logged-in user ID here)
            panthiId: viewModel.selectedPanthiId, // <-- ENSURE THIS ARGUMENT IS PRESENT
            completion: { result in // This is the completion handler
                DispatchQueue.main.async {
                    switch result {
                    case .success(let url):
                        self.approvalURL = url
                    case .failure(let error):
                        var friendlyMessage = "Could not create payment order."
                        if let paymentErr = error as? PaymentError { // Assuming PaymentError is your custom error enum
                            switch paymentErr {
                            case .serverError(let specificMsg): friendlyMessage += " Server error: \(specificMsg)"
                            case .invalidResponse: friendlyMessage += " Invalid response from server."
                            case .parseError(let specificMsg): friendlyMessage += " Error parsing server response: \(specificMsg)"
                            }
                        } else {
                            friendlyMessage += " Error: \(error.localizedDescription)"
                        }
                        self.paymentErrorMessage = friendlyMessage
                        self.showPaymentError = true
                    }
                }
            }
        )
    }
    
    private func handlePayPalRedirect(url: URL) {
        guard
            let comps     = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let payerId   = comps.queryItems?.first(where: { $0.name == "PayerID"  })?.value,
            let paymentIdFromRedirect = comps.queryItems?.first(where: { $0.name == "paymentId"})?.value
        else {
            paymentErrorMessage = "Invalid PayPal redirect URL."
            showPaymentError = true
            return
        }
        
        let eventIdInt = Int(event.id) // Convert event.id to Int
        // Retrieve ticketPurchaseId stored by PaymentManager after createOrder (if your backend returns it)
        // Using a distinct key for clarity if it was set by PaymentManager.createOrder's response parsing
        let ticketPurchaseId = UserDefaults.standard.integer(forKey: "ticketPurchaseId_from_createOrder")
        
        PaymentManager.shared.captureOrder(
            payerId: payerId,                     // From PayPal redirect
            paymentId: paymentIdFromRedirect,     // From PayPal redirect
            memberName: memberNameText,           // Contextual
            email: emailAddressText,              // Contextual
            phone: phoneText,                     // Contextual
            comments: "\(event.title) Tickets",   // Contextual
            type: "ticket",                       // Hardcoded as "ticket" for this view's purpose
            id: ticketPurchaseId != 0 ? ticketPurchaseId : nil, // Your app's ticket_purchase.id
            eventId: eventIdInt,                  // Your app's event_id (as Int)
            panthiId: viewModel.selectedPanthiId, // Pass the selectedPanthiId
            completion: { result in // <<<< THIS IS THE LABEL FOR THE TRAILING CLOSURE
                DispatchQueue.main.async {
                    switch result {
                    case .failure(let e):
                        var msg = "Could not confirm payment."
                        if let paymentErr = e as? PaymentError { // Assuming PaymentError is your custom enum
                            switch paymentErr {
                            case .serverError(let specificMsg): msg += " Server error: \(specificMsg)"
                            case .invalidResponse: msg += " Invalid response from server."
                            case .parseError(let specificMsg): msg += " Error parsing response: \(specificMsg)"
                            }
                        } else {
                            msg += " Error: \(e.localizedDescription)"
                        }
                        self.paymentErrorMessage = msg
                        self.showPaymentError = true
                    case .success(let confirmationResponse):
                        print("✅ Purchase success response: \(confirmationResponse)")
                        self.showPurchaseSuccess = true
                        UserDefaults.standard.removeObject(forKey: "ticketPurchaseId_from_createOrder") // Clean up
                    }
                }
            } // End of trailing closure
        ) // End of captureOrder call
    }
}
    // Helper for email validation (should be in a common utility file ideally)
    extension String {
        var isValidEmail: Bool {
            let emailRegEx = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
            let emailPred = NSPredicate(format:"SELF MATCHES %@", emailRegEx)
            return emailPred.evaluate(with: self)
        }
    }
