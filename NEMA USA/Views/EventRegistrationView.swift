//
//  RuchimelamRegistrationView.swift
//  NEMA USA
//
//  Created by Arjun on 4/20/25.
//

import SwiftUI
import UIKit

struct EventRegistrationView: View {
    let event: Event
    @Environment(\.presentationMode) private var presentationMode

    // fetch from your DB manager; replace with your actual API
    private let memberName: String = DatabaseManager.shared.currentUser?.name ?? "Unknown"
    private let email: String      = DatabaseManager.shared.currentUser?.email ?? ""

    @State private var count14Plus   = 0
    @State private var count8to13    = 0
    @State private var acceptedTerms = false
    @State private var showAlert     = false

    private var totalAmount: Int {
        count14Plus * 10 + count8to13 * 5
    }

    init(event: Event) {
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
            UIBarButtonItem.appearance().tintColor   = .white
        }
        UINavigationBar.appearance().tintColor = .white
        self.event = event
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Orange status bar header
            Color.orange
                .ignoresSafeArea(edges: .top)
                .frame(height: 56)

            ScrollView {
                VStack(spacing: 20) {
                    // MARK: – Page Title (no card)
                    Text("\(event.title) Registration")
                        .font(.title2).bold()
                        .padding(.horizontal)
                        .padding(.top, 16)

                    // MARK: – Profile Info Card
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your Information")
                            .font(.headline)
                        HStack {
                            Text("Name")
                            Spacer()
                            Text(memberName)
                        }
                        HStack {
                            Text("Email")
                            Spacer()
                            Text(email)
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)
                    .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 2)
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
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)
                    .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 2)
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
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)
                    .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 2)
                    .padding(.horizontal)

                    // MARK: – Buy Button
                    Button(action: { showAlert = true }) {
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
                    .alert("Purchase successful!", isPresented: $showAlert) {
                        Button("OK") { presentationMode.wrappedValue.dismiss() }
                    }
                }
                .background(Color(.systemBackground))
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }
}

