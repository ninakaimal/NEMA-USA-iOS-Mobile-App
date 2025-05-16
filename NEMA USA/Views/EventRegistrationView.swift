//
//  EventRegistrationView.swift
//  NEMA USA
//  Created by Arjun on 4/20/25.
//  Added PayPal integration by Arjun on 4/22/25
//

import SwiftUI
import UIKit

// Allow URL in .sheet(item:)
extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

struct EventRegistrationView: View {
    let event: Event
    @Environment(\.presentationMode) private var presentationMode

    // MARK: – Login / Member state
    @AppStorage("laravelSessionToken") private var authToken: String?
    @State private var showLoginSheet          = false
    @State private var pendingPurchase         = false

    // pull in user info into @State so SwiftUI refreshes it
    @State private var memberNameText   = ""
    @State private var emailAddressText = ""
    @State private var phoneText        = ""

    // MARK: – Ticket state
    @State private var AdultRate     = 0
    @State private var KidsRate      = 0
    @State private var acceptedTerms = false

    // MARK: – PayPal / Alerts
    @State private var showPurchaseConfirmation = false
    @State private var showPurchaseSuccess      = false
    @State private var approvalURL: URL?        = nil

    // to show payment errors on screen
    @State private var showPaymentError    = false
    @State private var paymentErrorMessage = ""

    private var totalAmount: Int {
        AdultRate * 10 + KidsRate * 2
    }

    init(event: Event) {
        self.event = event
        // UINavigationBar appearance setup…
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
    }

    var body: some View {
        content
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)

            // MARK: – Login sheet
            .sheet(isPresented: $showLoginSheet, onDismiss: {
                loadMemberInfo()
                if pendingPurchase {
                    showPurchaseConfirmation = true
                    pendingPurchase = false
                }
            }) {
                LoginView()
            }

            // MARK: – Confirmation alert
            .alert(
                "Confirm Purchase",
                isPresented: $showPurchaseConfirmation
            ) {
                Button("Cancel", role: .cancel) { }
                Button("Confirm") {
                    initiateMobilePayment()
                }
            } message: {
                Text("""
                     Adults: \(AdultRate)
                     Children: \(KidsRate)
                     Total: $\(totalAmount)
                     """)
            }

            // MARK: – Show payment errors
            .alert(
                "Payment Error",
                isPresented: $showPaymentError
            ) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(paymentErrorMessage)
            }

            // MARK: – Success alert
            .alert(
                "Purchase successful! Check \(emailAddressText)",
                isPresented: $showPurchaseSuccess
            ) {
                Button("OK") {
                    presentationMode.wrappedValue.dismiss()
                }
            } message: {
                EmptyView()
            }

            // MARK: – PayPal approval sheet
            .sheet(item: $approvalURL) { url in
              PayPalView(
                approvalURL:        url,
                showPaymentError:   $showPaymentError,
                paymentErrorMessage:$paymentErrorMessage,
                showPurchaseSuccess:$showPurchaseSuccess,
                comments:           "Mobile App Ticket Purchase",
                successMessage:     "Your tickets have been purchased!"
              )
            }

            // MARK: – Handle PayPal redirect
            .onOpenURL { url in
                guard
                    let comps     = URLComponents(url: url, resolvingAgainstBaseURL: false),
                    let payerId   = comps.queryItems?.first(where: { $0.name == "PayerID"  })?.value
                else {
                    return
                }

                PaymentManager.shared.captureOrder(
                    payerId: payerId,
                    memberName: memberNameText,
                    email: emailAddressText,
                    phone: phoneText
                ) { result in
                    DispatchQueue.main.async {
                        switch result {
                        case .failure(let e):
                            paymentErrorMessage = "Could not capture order: \(e)"
                            showPaymentError = true
                        case .success:
                            showPurchaseSuccess = true
                        }
                    }
                }
            }
            .onAppear(perform: loadMemberInfo)
    }

    /// Pulled the big layout out into a helper to keep `body` lean.
    private var content: some View {
        ZStack(alignment: .top) {
            Color.orange
                .ignoresSafeArea(edges: .top)
                .frame(height: 56)

            ScrollView {
                VStack(spacing: 24) {
                    Text("\(event.title) Tickets")
                        .font(.title2).bold()
                        .padding(.horizontal)
                        .padding(.top, 16)

                    infoCard
                    ticketCard
                    termsCard
                    purchaseButton

                    Spacer(minLength: 32)
                }
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

    private var ticketCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Adults (13+ yrs): $10 each").font(.headline)
                Stepper("\(AdultRate)", value: $AdultRate, in: 0...20)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Children (4–13 yrs): $2 each").font(.headline)
                Stepper("\(KidsRate)", value: $KidsRate, in: 0...30)
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
                Text("$\(totalAmount)").font(.headline)
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
                Button("Purchase") {
                    if memberNameText.isEmpty {
                        paymentErrorMessage = "Name is required."
                        showPaymentError = true
                    } else if emailAddressText.isEmpty {
                        paymentErrorMessage = "Email is required."
                        showPaymentError = true
                    } else if phoneText.isEmpty {
                        paymentErrorMessage = "Phone number is required."
                        showPaymentError = true
                    } else if !acceptedTerms {
                        paymentErrorMessage = "You must accept the terms & conditions."
                        showPaymentError = true
                    } else if totalAmount == 0 {
                        paymentErrorMessage = "You must select at least one ticket."
                        showPaymentError = true
                    } else {
                        showPurchaseConfirmation = true
                    }
                }
                .disabled(!acceptedTerms || totalAmount == 0)
        .padding().frame(maxWidth: .infinity)
        .background((acceptedTerms && totalAmount > 0 && !emailAddressText.isEmpty) ? Color.orange : Color.gray)
        .foregroundColor(.white).cornerRadius(10)
        .padding(.horizontal)
    }

    private func loadMemberInfo() {
        memberNameText = UserDefaults.standard.string(forKey: "memberName") ?? ""
        emailAddressText = UserDefaults.standard.string(forKey: "emailAddress") ?? ""
        phoneText = UserDefaults.standard.string(forKey: "phoneNumber") ?? ""
    }

    private func initiateMobilePayment() {
        PaymentManager.shared.createOrder(amount: "\(totalAmount)", eventTitle: event.title) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let url):
                    self.approvalURL = url
                case .failure(let error):
                    paymentErrorMessage = "Could not create order: \(error)"
                    showPaymentError = true
                }
            }
        }
    }
}
