//
//  EventRegistrationView.swift
//  NEMA USA
//  Created by Arjun on 4/20/25.
//  Added PayPal integration by Arjun on 4/22/25
//

import SwiftUI
import UIKit
import SafariServices
import SwiftSoup   // still needed by your scraping/network code

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

    // NEW: to show payment errors on screen
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
                    // 🔐 DEBUG: print out the JWT we're about to use
                    let jwt = DatabaseManager.shared.jwtApiToken ?? "nil"
                    print("🔐 [EventRegistration] JWT for order: \(jwt)")

                    let amt = String(totalAmount)
                    PaymentManager.shared.createOrder(amount: amt) { result in
                        switch result {
                        case .failure(let err):
                            print("❌ [EventRegistration] createOrder failed:", err)
                            // surface in UI
                            paymentErrorMessage = "Could not create order: \(err)"
                            showPaymentError = true
                        case .success(let url):
                            print("✅ [EventRegistration] got approval URL:", url)
                            approvalURL = url
                        }
                    }
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
                "Purchase successful!",
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
                SafariView(url: url)
            }

            // MARK: – Handle PayPal redirect
            .onOpenURL { url in
                guard
                    let comps   = URLComponents(url: url, resolvingAgainstBaseURL: false),
                    let orderID = comps.queryItems?.first(where: { $0.name == "token" })?.value
                else { return }

                // 🔐 DEBUG: print JWT again on capture
                let jwt = DatabaseManager.shared.jwtApiToken ?? "nil"
                print("🔐 [EventRegistration] JWT for capture: \(jwt)")

                PaymentManager.shared.captureOrder(
                    orderID:   orderID,
                    amount:    String(totalAmount),
                    approveUrl: approvalURL?.absoluteString ?? ""
                ) { result in
                    switch result {
                    case .failure(let e):
                        print("❌ [EventRegistration] captureOrder failed:", e)
                        paymentErrorMessage = "Could not capture order: \(e)"
                        showPaymentError = true
                    case .success:
                        print("✅ [EventRegistration] captureOrder succeeded")
                        showPurchaseSuccess = true
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
                    // MARK: – Page Title
                    Text("\(event.title) Registration")
                        .font(.title2).bold()
                        .padding(.horizontal)
                        .padding(.top, 16)

                    // MARK: – Profile Info Card
                    infoCard

                    // MARK: – Ticket Selection Card
                    ticketCard

                    // MARK: – Terms & Total Card
                    termsCard

                    // MARK: – Purchase Button
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

            if authToken == nil {
                VStack(spacing: 8) {
                    Text("Login to view").foregroundColor(.secondary)
                    Button("Login") {
                        pendingPurchase = false
                        showLoginSheet  = true
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                }
                .frame(maxWidth: .infinity)
            } else {
                Group {
                    HStack {
                        Text("Name").foregroundColor(.secondary)
                        Spacer()
                        Text(memberNameText).fontWeight(.medium)
                    }
                    HStack {
                        Text("Email").foregroundColor(.secondary)
                        Spacer()
                        Text(emailAddressText).fontWeight(.medium)
                    }
                    HStack {
                        Text("Phone").foregroundColor(.secondary)
                        Spacer()
                        TextField("Phone", text: $phoneText)
                            .multilineTextAlignment(.trailing)
                            .font(.body)
                    }
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16)
                        .fill(Color(.secondarySystemBackground)))
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
        .background(RoundedRectangle(cornerRadius: 16)
                        .fill(Color(.secondarySystemBackground)))
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
            Toggle(isOn: $acceptedTerms) {
                Text("I accept the terms & conditions").font(.subheadline)
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16)
                        .fill(Color(.secondarySystemBackground)))
        .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 3)
        .padding(.horizontal)
    }

    private var purchaseButton: some View {
        Button {
            print("⚡️ Purchase tapped – terms=\(acceptedTerms) total=\(totalAmount) auth=\(authToken ?? "nil")")
            if authToken == nil {
                pendingPurchase = true
                showLoginSheet  = true
            } else {
                showPurchaseConfirmation = true
            }
        } label: {
            Text("Purchase Tickets")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background((acceptedTerms && totalAmount > 0) ? Color.orange : Color.gray)
                .foregroundColor(.white)
                .cornerRadius(10)
        }
        .disabled(!acceptedTerms || totalAmount == 0)
        .padding(.horizontal)
        .padding(.bottom, 24)
    }

    // MARK: – Helpers

    private func loadMemberInfo() {
        guard let u = DatabaseManager.shared.currentUser else { return }
        memberNameText   = u.name
        emailAddressText = u.email
        phoneText        = u.phone
    }
}

// SafariView wrapper
fileprivate struct SafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }
    func updateUIViewController(
        _ uiViewController: SFSafariViewController,
        context: Context
    ) { }
}
