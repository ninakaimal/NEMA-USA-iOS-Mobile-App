//
//  EventRegistrationView.swift
//  NEMA USA
//  Created by Arjun on 4/20/25.
//

import SwiftUI
import UIKit

struct EventRegistrationView: View {
    let event: Event
    @Environment(\.presentationMode) private var presentationMode

    // MARK: – Login / Member state
    @AppStorage("authToken") private var authToken: String?
    @State private var showLoginSheet       = false
    @State private var pendingPurchase      = false

    // pull in user info into @State so SwiftUI refreshes it
    @State private var memberNameText       = ""
    @State private var emailAddressText     = ""

    // MARK: – Ticket state
    @State private var count14Plus   = 0
    @State private var count8to13    = 0
    @State private var acceptedTerms = false

    // MARK: – Alerts
    @State private var showPurchaseConfirmation = false
    @State private var showPurchaseSuccess      = false

    private var totalAmount: Int {
        count14Plus * 10 + count8to13 * 5
    }

    init(event: Event) {
        self.event = event
        // match EventDetail nav‑bar styling
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
            // Orange status bar header
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
                            // LOGGED OUT STATE
                            VStack(spacing: 8) {
                                Text("Login to view")
                                    .foregroundColor(.secondary)
                                Button("Login") {
                                    showLoginSheet = true
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.orange)
                            }
                            .frame(maxWidth: .infinity)
                        } else {
                            // LOGGED IN STATE
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
                            Text("Adults (14+ years) – $10 each")
                                .font(.headline)
                            Stepper("\(count14Plus)", value: $count14Plus, in: 0...20)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Children (8–13 years) – $5 each")
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
                            // need login first
                            pendingPurchase  = true
                            showLoginSheet   = true
                        } else {
                            // ready to confirm
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

        // when not logged in → sheet to login
        .sheet(isPresented: $showLoginSheet) {
            LoginView()
        }
        // after login: refresh user info & possibly kick off purchase confirm
        .onChange(of: authToken) { newToken in
            if newToken != nil {
                // pull in fresh user data
                if let u = DatabaseManager.shared.currentUser {
                    memberNameText   = u.name
                    emailAddressText = u.email
                }
                // if user tapped purchase before login
                if pendingPurchase {
                    showPurchaseConfirmation = true
                    pendingPurchase = false
                }
                showLoginSheet = false
            }
        }
        // initialize from any cached user
        .onAppear {
            if let u = DatabaseManager.shared.currentUser {
                memberNameText   = u.name
                emailAddressText = u.email
            }
        }

        // MARK: – Confirmation Alert
        .alert(
            "Confirm Purchase",
            isPresented: $showPurchaseConfirmation,
            actions: {
                Button("Cancel", role: .cancel) { }
                Button("Confirm") {
                    showPurchaseSuccess = true
                }
            },
            message: {
                Text("""
                     Adults: \(count14Plus)
                     Children: \(count8to13)
                     Total: $\(totalAmount)
                     """)
            }
        )

        // MARK: – Success Feedback
        .alert(
            "Purchase successful!",
            isPresented: $showPurchaseSuccess,
            actions: {
                Button("OK") {
                    presentationMode.wrappedValue.dismiss()
                }
            },
            message: { EmptyView() }
        )
    }
}

