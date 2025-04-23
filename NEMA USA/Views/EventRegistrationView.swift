//
//  EventRegistrationView.swift
//  NEMA USA
//  Created by Arjun on 4/20/25.
//  Added PayPal integration by Arjun on 4/22/2025

import SwiftUI
import UIKit
import SafariServices

// Allow URL in .sheet(item:)
extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

struct EventRegistrationView: View {
    let event: Event
    @Environment(\.presentationMode) private var presentationMode

    // MARK: – Login / Member state
    @AppStorage("authToken") private var authToken: String?
    @State private var showLoginSheet          = false
    @State private var pendingPurchase         = false

    // pull in user info into @State so SwiftUI refreshes it
    @State private var memberNameText          = ""
    @State private var emailAddressText        = ""

    // MARK: – Ticket state
    @State private var count14Plus             = 0
    @State private var count8to13              = 0
    @State private var acceptedTerms           = false

    // MARK: – PayPal / Alerts
    @State private var showPurchaseConfirmation = false
    @State private var showPurchaseSuccess      = false
    @State private var approvalURL: URL?        = nil

    private var totalAmount: Int {
        count14Plus * 10 + count8to13 * 5
    }

    init(event: Event) {
        self.event = event
        if #available(iOS 15.0, *) {
            let appearance = UINavigationBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = UIColor(Color.orange)
            appearance.titleTextAttributes = [.foregroundColor: UIColor.white]
            appearance.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
            UINavigationBar.appearance().standardAppearance   = appearance
            UINavigationBar.appearance().scrollEdgeAppearance = appearance
        } else {
            UINavigationBar.appearance().barTintColor = .orange
        }
        UINavigationBar.appearance().tintColor = .white
    }

    var body: some View {
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
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Your Information")
                            .font(.headline)
                            .padding(.bottom, 4)

                        if authToken == nil {
                            VStack(spacing: 8) {
                                Text("Login to view")
                                    .foregroundColor(.secondary)
                                Button("Login") {
                                    pendingPurchase = false
                                    showLoginSheet = true
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.orange)
                            }
                            .frame(maxWidth: .infinity)
                        } else {
                            HStack {
                                Text("Name")
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(memberNameText)
                                    .fontWeight(.medium)
                            }
                            HStack {
                                Text("Email")
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(emailAddressText)
                                    .fontWeight(.medium)
                            }
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(.secondarySystemBackground))
                    )
                    .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 3)
                    .padding(.horizontal)

                    // MARK: – Ticket Selection Card
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Adults (14+ years) – $10 each")
                                .font(.headline)
                            Stepper("\(count14Plus)", value: $count14Plus, in: 0...20)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Children (8–13 years) – $5 each")
                                .font(.headline)
                            Stepper("\(count8to13)", value: $count8to13, in: 0...30)
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(.secondarySystemBackground))
                    )
                    .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 3)
                    .padding(.horizontal)

                    // MARK: – Terms & Total Card
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("Total cost:")
                                .font(.headline)
                            Spacer()
                            Text("$\(totalAmount)")
                                .font(.headline)
                        }
                        Toggle(isOn: $acceptedTerms) {
                            Text("I accept the terms & conditions")
                                .font(.subheadline)
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(.secondarySystemBackground))
                    )
                    .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 3)
                    .padding(.horizontal)

                    // MARK: – Purchase Button
                    Button {
                        if authToken == nil {
                            pendingPurchase  = true
                            showLoginSheet   = true
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

                    Spacer(minLength: 32)
                }
                .background(Color(.systemBackground))
            }
        }
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
            isPresented: $showPurchaseConfirmation,
            actions: {
                Button("Cancel", role: .cancel) {}
                Button("Confirm") { createAndOpenApproval() }
            },
            message: {
                Text("""
                     Adults: \(count14Plus)
                     Children: \(count8to13)
                     Total: $\(totalAmount)
                     """)
            }
        )

        // MARK: – Success alert
        .alert(
            "Purchase successful!",
            isPresented: $showPurchaseSuccess,
            actions: {
                Button("OK") { presentationMode.wrappedValue.dismiss() }
            },
            message: { EmptyView() }
        )

        // MARK: – PayPal approval sheet
        .sheet(item: $approvalURL) { url in
            SafariView(url: url)
        }

        // MARK: – Handle PayPal redirect
        .onOpenURL { url in
            guard
                let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
                comps.host == "paypalpay",
                let token = comps.queryItems?.first(where: { $0.name == "token" })?.value
            else { return }
            captureOrder(orderID: token)
        }
        .onAppear(perform: loadMemberInfo)
    }

    // MARK: – Backend calls

    private func createAndOpenApproval() {
        let url = URL(string: "https://nema-api.kanakaagro.in/api/create-paypal-order")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONEncoder().encode([
            "amount": "\(totalAmount)",
            "currency": "USD"
        ])
        URLSession.shared.dataTask(with: req) { data, _, _ in
            guard
                let data = data,
                let resp = try? JSONDecoder().decode([String: String].self, from: data),
                let href = resp["approveUrl"],
                let approval = URL(string: href)
            else { return }
            DispatchQueue.main.async { approvalURL = approval }
        }.resume()
    }

    private func captureOrder(orderID: String) {
        // Convert your Event.id → Int
        guard Int(event.id) != nil else {
            print("Invalid event.id: \(event.id)")
            return
        }

        // Compute how many tickets total
        _ = count14Plus + count8to13

        // Build the request
        let url = URL(string: "https://nema-api.kanakaagro.in/api/capture-paypal-order")!
          var req = URLRequest(url: url)
          req.httpMethod = "POST"
          req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Send orderID, eventTktId, amount, AND no (ticketCount)
        
        let body: [String:Any] = [
          "orderID":    orderID,
          "amount":     totalAmount,
          "approveUrl": approvalURL?.absoluteString ?? ""
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        // Remember to include your JWT in the header so the server can pull userId:
        if let token = DatabaseManager.shared.authToken {
          req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        URLSession.shared.dataTask(with: req) { _, _, _ in
          DispatchQueue.main.async { showPurchaseSuccess = true }
        }.resume()
    }
    
    // MARK: – Helpers

    private func loadMemberInfo() {
        guard let u = DatabaseManager.shared.currentUser else { return }
        memberNameText   = u.name
        emailAddressText = u.email
    }
}

// SafariView wrapper
fileprivate struct SafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }
    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
