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
    @State private var userInitiatedLogin = false
    @State private var attemptedLoginForMemberPrice = false // state variable to track if user *chose* to login from this screen
    
    // User Info state variables (managed by the view for now)
    @State private var memberNameText   = ""
    @State private var emailAddressText = ""
    @State private var phoneText        = ""
    
    // MARK: – Ticket state
    @State private var acceptedTerms = false
    
    // MARK: – PayPal / Alerts
    @State private var isProcessingPayment = false
    @State private var showPurchaseConfirmation = false
    @State private var showPurchaseSuccess      = false
    @State private var approvalURL: URL?        = nil
    @State private var showPaymentError    = false
    @State private var paymentErrorMessage = ""
    
    @State private var dummyPaymentConfirmationForPayPalView: PaymentConfirmationResponse? = nil
    
    init(event: Event) {
        self.event = event
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
    
    
    private var isUserLoggedInAndHasActiveMembership: Bool {
        guard DatabaseManager.shared.jwtApiToken != nil, // User is logged in
              let currentUser = DatabaseManager.shared.currentUser else {
            return false // Not logged in or no user profile available
        }
        // UserProfile.isMember already checks for a valid, non-expired membership date
        return currentUser.isMember
    }
    
    var body: some View {
        content
            .navigationTitle(event.isRegWaitlist == true ? "\(event.title) Waitlist" : "\(event.title) Tickets") // Set title here
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showLoginSheet, onDismiss: {
                loadMemberInfo()
                let refreshDelay = attemptedLoginForMemberPrice ? 0.5 : 0.25 // Slightly longer if member price was the goal
                DispatchQueue.main.asyncAfter(deadline: .now() + refreshDelay) {
                    self.loadMemberInfo()
                    self.viewModel.objectWillChange.send()
                }

                // This block seems fine, assuming userInitiatedLogin is correctly declared as @State
                if userInitiatedLogin {
                    // viewModel.objectWillChange.send() was called above, UI should update.
                    userInitiatedLogin = false
                }

                if pendingPurchase {
                    if DatabaseManager.shared.jwtApiToken != nil {
                        validateAndShowPurchaseConfirmation()
                    } else {
                        pendingPurchase = false
                    }
                }
                attemptedLoginForMemberPrice = false
            }) {
                LoginView() // Make sure LoginView updates DatabaseManager.shared states
            }
            .alert(
                "Confirm \(event.isRegWaitlist == true ? "Join Waitlist" : "Purchase")",
                isPresented: $showPurchaseConfirmation
            ) {
                Button("Cancel", role: .cancel) { }
                Button("Confirm") {
                    isProcessingPayment = true
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
                "Success!", // Updated title
                isPresented: $showPurchaseSuccess
            ) {Button("OK") { presentationMode.wrappedValue.dismiss() }
            } message: {
                if event.isRegWaitlist == true {
                    Text("You have been added to the waitlist for \(event.title). Check your email \(emailAddressText) for confirmation.")
                } else {
                    Text("Purchase successful! Check your email \(emailAddressText) for confirmation.")
                }
            }
        
        // MARK: – PayPal approval sheet
            .sheet(item: $approvalURL) { url in
                PayPalView(
                    approvalURL:        url,
                    showPaymentError:   $showPaymentError,
                    paymentErrorMessage:$paymentErrorMessage,
                    showPurchaseSuccess:$showPurchaseSuccess,
                    paymentConfirmationData: $dummyPaymentConfirmationForPayPalView,
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
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                DispatchQueue.main.async {
                    loadMemberInfo()
                    viewModel.objectWillChange.send()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .didReceiveJWT)) { _ in
                DispatchQueue.main.async {
                    loadMemberInfo()
                    viewModel.objectWillChange.send()
                    print("✅ [EventRegView] Refreshed after JWT received")
                }
            }
    }
    
    private var content: some View {
        ZStack(alignment: .top) {
            Color.orange
                .ignoresSafeArea(edges: .top)
                .frame(height: 56)
            
            ScrollView {
                VStack(spacing: 24) {
                    infoCard
                    
                    if viewModel.isLoading {
                        ProgressView("Loading ticket options...")
                            .padding(.vertical, 40)
                    } else if let errorMsg = viewModel.errorMessage {
                        Text("Error loading options: \(errorMsg)")
                            .foregroundColor(.red)
                            .padding()
                    } else {
                        ticketSelectionCard // Dynamic ticket types
                        if event.usesPanthi ?? false { // Check the flag from the Event model
                            panthiSelectionCard
                        }
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
              
                // Add Login/Member Status Button
                if DatabaseManager.shared.jwtApiToken == nil { // Only show if not logged in
                    Button("Login for Member Pricing!") {
                        userInitiatedLogin = true
                        attemptedLoginForMemberPrice = true
                        pendingPurchase = false
                        showLoginSheet = true
                    }
                    .padding(.top, 8)
                    Text("You can also proceed as a guest with non-member prices")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else if let user = DatabaseManager.shared.currentUser {
                     Text(user.isMember ? "Member prices are automatically applied" : "Not a NEMA member, non-member prices apply. Tap the Account icon below for membership options.")
                        .font(.caption)
                        .foregroundColor(user.isMember ? .green : .orange)
                        .padding(.top, 5)
                }
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
        // Check if the event is configured to use Panthis
        if event.usesPanthi == true { // Explicitly check for true
            if viewModel.isLoading && viewModel.availablePanthis.isEmpty { // Show loading if panthis are expected but not yet loaded
                ProgressView("Loading time slots...")
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
                    .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 3)
                    .padding(.horizontal)
            } else if !viewModel.availablePanthis.isEmpty { // Panthis are loaded
                VStack(alignment: .leading, spacing: 12) {
                    Text("Please select a Panthi / Time Slot")
                        .font(.headline)
                    
                    Picker("Select Slot", selection: $viewModel.selectedPanthiId) {
                        Text("Select Panthi").tag(nil as Int?) // Placeholder for no selection
                        ForEach(viewModel.availablePanthis.filter { $0.availableSlots > 0 || $0.id == viewModel.selectedPanthiId }) { panthi in
                            Text(panthi.name)
                                .tag(panthi.id as Int?)
                        }
                    }
                    .pickerStyle(MenuPickerStyle()) // Standard dropdown style
                    .padding(.vertical, 5)
                    .background(Color(.tertiarySystemBackground).opacity(0.7))
                    .cornerRadius(8)
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
                .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 3)
                .padding(.horizontal)
            } else if !viewModel.isLoading && viewModel.errorMessage == nil { // Done loading, no error, but still no panthis
                Text("No time slots (Panthi) are currently available for this event. Please contact arts@nemausa.org")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
                    .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 3)
                    .padding(.horizontal)
            }
        }
    }
    
    // MARK: - Dynamic Ticket Selection Card

    // New struct for displaying and interacting with a single ticket type
    private struct TicketTypeRowView: View {
        let ticketType: EventTicketType
        @Binding var quantity: Int
        let price: Double // Pass the calculated price
        let isDisabled: Bool // Pass whether this row should be disabled

        var body: some View {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(ticketType.typeName):")
                        .font(.headline)
                        .opacity(isDisabled ? 0.6 : 1.0) // Visually dim text if disabled

                    Text("$\(String(format: "%.2f", price)) each")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .opacity(isDisabled ? 0.6 : 1.0)

                    // Informative text if a member ticket is disabled
                    if isDisabled && (ticketType.isTicketTypeMemberExclusive ?? false) {
                        Text("(Member Pricing - Login or Renew Membership)")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }
                Spacer()
                Stepper(
                    value: $quantity, // Use the direct binding passed from parent
                    in: 0...20       // Using a fixed range (e.g., 0 to 20)
                ) {
                    Text("\(quantity)")
                        .font(.system(size: 18, weight: .medium))
                        .frame(minWidth: 25, alignment: .center)
                }
                .frame(width: 120) // Adjust width as needed
                .disabled(isDisabled) // Disable the stepper based on passed-in state
                .opacity(isDisabled ? 0.5 : 1.0) // Further visual cue for disabled stepper
            }
        }
    }

    // Now use the struct above to populate ticket selection card
    private var ticketSelectionCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            if viewModel.availableTicketTypes.isEmpty && !viewModel.isLoading && viewModel.errorMessage == nil {
                Text("Ticket information will be available soon.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 20)
            } else {
                // 🔸 Filter ticket types based on membership (authoritative source)
                let isMember = DatabaseManager.shared.currentUser?.isMember ?? false
                let visibleTicketTypes = viewModel.availableTicketTypes.filter { ticket in
                    let mirror = Mirror(reflecting: ticket)
                    var isExclusiveFlag: Bool?
                    var typeName: String?

                    for child in mirror.children {
                        guard let label = child.label?.lowercased() else { continue }
                        if (label == "is_ticket_type_member_exclusive" || label == "istickettypememberexclusive"),
                           let val = child.value as? Bool {
                            isExclusiveFlag = val
                        }
                        if (label == "type_name" || label == "typename" || label == "type"),
                           let name = child.value as? String {
                            typeName = name
                        }
                    }

                    // Fallback inference from type name if backend flag is missing or incorrect
                    let inferredExclusive: Bool = {
                        guard var name = typeName?.lowercased() else { return false }
                        name = name.replacingOccurrences(of: ":", with: "")
                                   .replacingOccurrences(of: "  ", with: " ")
                                   .trimmingCharacters(in: .whitespacesAndNewlines)
                        let hasMember = name.contains(" member")
                            || name.hasSuffix("member")
                            || name.hasPrefix("member")
                            || name.contains("(member)")
                        let hasNonMember = name.contains("non-member")
                            || name.contains("non member")
                            || name.contains("nonmember")
                            || name.contains("nonmembers")
                        return hasMember && !hasNonMember
                    }()

                    let isExclusive = (isExclusiveFlag ?? false) || inferredExclusive
                    return isMember || !isExclusive
                }

                // 🔸 Render filtered list
                ForEach(visibleTicketTypes, id: \.id) { ticketType in

                    // Calculate disabled state clearly before passing to the row view
                    let isMemberExclusiveForThisType = ticketType.isTicketTypeMemberExclusive ?? false
                    let isActiveMember = self.isUserLoggedInAndHasActiveMembership // Uses UserProfile.isMember
                    let shouldDisableThisRowStepper = isMemberExclusiveForThisType && !isActiveMember
                    
                    // Create a binding to the specific quantity for this ticket type
                    let quantityBinding = Binding(
                        get: { viewModel.ticketQuantities[ticketType.id] ?? 0 },
                        set: { newValue in
                            // The TicketTypeRowView's Stepper will be disabled,
                            // but this check in the binding's setter is an extra safeguard.
                            if !shouldDisableThisRowStepper {
                               viewModel.ticketQuantities[ticketType.id] = max(0, newValue)
                            }
                        }
                    )
                    
                    TicketTypeRowView(
                        ticketType: ticketType,
                        quantity: quantityBinding, // Pass the specific binding
                        price: viewModel.price(for: ticketType), // Calculate price once
                        isDisabled: shouldDisableThisRowStepper  // Pass the calculated disabled state
                    )
                    
                    // Add a divider unless it's the last item in the list
                    if visibleTicketTypes.last?.id != ticketType.id {
                        Divider()
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
                    Text("**Food Allergy Disclaimer:** Meals may contain allergens. We cannot guarantee allergen-free food. Consume at your own risk.")
                    Text("**Firecrackers Disclaimer:** Fireworks may be used at certain events like Diwali; NEMA not responsible for injuries or damages.")
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
        if event.isRegON ?? false {
            let isWaitlist = event.isRegWaitlist == true
            let buttonText = isWaitlist ? "Join Waitlist" : "Purchase"
            let canProceed = viewModel.canProceedToPurchase(
                acceptedTerms: acceptedTerms,
                eventUsesPanthi: event.usesPanthi ?? false,
                availablePanthisNonEmpty: !memberNameText.isEmpty && !emailAddressText.isEmpty && !phoneText.isEmpty && emailAddressText.isValidEmail
            )
        return AnyView(
            Button(action: {
                validateAndShowPurchaseConfirmation()
        }) {
            // The content of the button changes based on 'isProcessingPayment'
            if isProcessingPayment {
                HStack {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white)) // Style for white spinner
                        .padding(.trailing, 5) // Optional spacing
                    Text("Processing...")
                }
            } else {
                Text(buttonText)
            }
        }
        .disabled(!canProceed)
        .padding()
        .frame(maxWidth: .infinity)
        .background(canProceed ? Color.orange : Color.gray)
        .foregroundColor(.white)
        .cornerRadius(10)
        .padding(.horizontal)
    )
    }   else {
        // --- If Registration is OFF, show a disabled "Tickets Closed" button ---
        return AnyView(
            Text("Ticketing Closed")
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.gray) // Use a distinct disabled color
                .cornerRadius(10)
                .padding(.horizontal)
        )
    }
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
        // Validate user-entered info first - this is for guest or logged-in user
        guard !memberNameText.isEmpty else {
            paymentErrorMessage = "Please provide your Full Name to proceed.";
            showPaymentError = true; return
        }
        guard !emailAddressText.isEmpty, emailAddressText.isValidEmail else {
            paymentErrorMessage = "A valid Email Address is required.";
            showPaymentError = true; return
        }
        guard !phoneText.isEmpty else {
            paymentErrorMessage = "Your Phone Number is required.";
            showPaymentError = true; return
        }
        
        // Other existing validations
        guard acceptedTerms else {
            paymentErrorMessage = "You must accept the terms & conditions.";
            showPaymentError = true; return
        }
        guard viewModel.totalAmount > 0 else {
            paymentErrorMessage = "Please select at least one ticket.";
            showPaymentError = true; return
        }
        if event.usesPanthi ?? false && !viewModel.availablePanthis.isEmpty && viewModel.selectedPanthiId == nil {
            paymentErrorMessage = "Please select a time slot/Panthi for this event."
            showPaymentError = true; return
        }
        
        // If the user is NOT logged in (is a guest) AND they have filled in their details,
        // we can proceed to show the purchase confirmation.
        // If they ARE logged in, we also proceed.
        // The `initiateMobilePayment()` function will handle sending data appropriately
        // (including the JWT if logged in, or just guest details if not).
        
        // The behavior of forcing login when `pendingPurchase` is true after `LoginView` dismisses
        // will still work if the user *chose* to login via the "Login for Member Pricing" button.
        // This specific `validateAndShowPurchaseConfirmation` is for when the "Purchase" button is tapped directly.

        showPurchaseConfirmation = true // Proceed to show purchase confirmation
    }
    
    private func initiateMobilePayment() {
        UserDefaults.standard.set(event.id, forKey: "eventId") // Storing String event.id
        UserDefaults.standard.set(event.title, forKey: "item")
        
        guard let eventIDInt = Int(event.id) else { // Convert String event.id to Int
            paymentErrorMessage = "Invalid Event ID."
            showPaymentError = true
            isProcessingPayment = false
            return
        }
        
        var lineItemsPayload: [[String: Any]] = []
        for ticketType in viewModel.availableTicketTypes {
            if let quantity = viewModel.ticketQuantities[ticketType.id], quantity > 0 {
                lineItemsPayload.append([
                    "ticket_type_id": ticketType.id,
                    "quantity": quantity
                ])
            }
        }
        
        print("✅ [EventRegView] Constructed lineItemsPayload: \(lineItemsPayload)")
        
        // CHECK IF WAITLIST - Skip PayPal if waitlisted
        if event.isRegWaitlist == true {
            print("✅ [EventRegView] Waitlist registration - skipping PayPal")
            
            // Call the same createOrder API but it will handle waitlist differently
            PaymentManager.shared.createOrder(
                amount: "0.00",  // Waitlist is free
                eventTitle: event.title,
                eventID: eventIDInt,
                email: emailAddressText,
                name: memberNameText,
                phone: phoneText,
                membershipType: nil,
                packageId: nil,
                packageYears: nil,
                userId: nil,
                panthiId: viewModel.selectedPanthiId,
                lineItems: lineItemsPayload,
                completion: { result in
                    DispatchQueue.main.async {
                        self.isProcessingPayment = false
                        switch result {
                        case .success(_):
                            // For waitlist, we don't need PayPal URL, just show success
                            self.showPurchaseSuccess = true
                        case .failure(let error):
                            var friendlyMessage = "Could not complete waitlist registration."
                            if let paymentErr = error as? PaymentError {
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
        } else {
            // Regular purchase flow with PayPal
            
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
                panthiId: viewModel.selectedPanthiId,
                lineItems: lineItemsPayload,
                completion: { result in // This is the completion handler
                    DispatchQueue.main.async {
                        self.isProcessingPayment = false
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
    } // end of file
