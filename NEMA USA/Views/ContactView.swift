//
//  ContactView.swift
//  NEMA USA
//  Created by Arjun on 4/20/25.
//  Updated by Sajith on 4/22/25
//

import SwiftUI
import UIKit

struct ContactView: View {
    @State private var name         = ""
    @State private var email        = ""
    @State private var phone        = ""
    @State private var subject      = ""
    @State private var description  = ""
    @State private var isSubmitted  = false
    @State private var isLoading    = false
    @State private var errorMessage = ""

    // ──────────────────────────────────────────────────────────────────────
    // 1) Fill in your Mailjet credentials & sender/recipient here:
    private let mailjetPublicKey  = "62bce36df049d1a0af07a06ffd3dd99a"
    private let mailjetPrivateKey = "5da699c98d3ac10773284a0f1d331f81"
    private let mailFromEmail     = "webadmin@nemausa.org"
    private let mailFromName      = "NEMA USA App"
    private let mailToEmail       = "webadmin@nemausa.org"
    private let mailToName        = "NEMA Team"
    // ──────────────────────────────────────────────────────────────────────

    var body: some View {
        NavigationView {
            ZStack(alignment: .top) {
                Color.orange
                    .ignoresSafeArea(edges: .top)
                    .frame(height: 56)

                VStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("We'd love to hear from you! Please fill out the form below.")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                                .padding(.bottom, 8)

                            Group {
                                ContactField(title: "Name (Optional)",
                                             text: $name,
                                             placeholder: "Your name",
                                             icon: "person")
                                ContactField(title: "Email (Optional)",
                                             text: $email,
                                             placeholder: "your.email@example.com",
                                             icon: "envelope")
                                ContactField(title: "Phone Number (Optional)",
                                             text: $phone,
                                             placeholder: "Your phone number",
                                             icon: "phone")
                                ContactField(title: "Subject",
                                             text: $subject,
                                             placeholder: "Message subject",
                                             icon: "text.alignleft")
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Description")
                                    .font(.subheadline)
                                    .foregroundColor(.primary)
                                TextEditor(text: $description)
                                    .frame(height: 100)
                                    .padding(10)
                                    .background(Color(.secondarySystemBackground))
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.orange, lineWidth: 0.2)
                                    )
                            }

                            if !errorMessage.isEmpty {
                                Text(errorMessage)
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                            if isSubmitted {
                                Text("✅ Feedback submitted, Thank you!")
                                    .font(.subheadline)
                                    .foregroundColor(.orange)
                            }

                            Button(action: submitForm) {
                                HStack {
                                    Image(systemName: "paperplane.fill")
                                    Text(isLoading ? "Submitting..." : "Submit")
                                        .bold()
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.orange)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                            }
                            .disabled(isLoading)

                            Text("Personal information is optional to support anonymity")
                                .font(.footnote)
                                .foregroundColor(.gray)
                                .padding(.top, 20)
                        }
                        .padding()
                        .background(Color(.systemBackground))
                    }
                }
            }
            .navigationTitle("Send Feedback")
            .navigationBarTitleDisplayMode(.inline)
            .accentColor(.primary)
        }
    }

    private func submitForm() {
        errorMessage = ""
        isSubmitted = false

        guard !subject.isEmpty, !description.isEmpty else {
            errorMessage = "Subject and description are required."
            return
        }

        isLoading = true

        // Build Mailjet v3.1 payload
        let mjPayload: [String: Any] = [
            "Messages": [[
                "From": [
                    "Email": mailFromEmail,
                    "Name":  mailFromName
                ],
                "To": [[
                    "Email": mailToEmail,
                    "Name":  mailToName
                ]],
                "Subject": "📩 App Feedback: \(subject)",
                "TextPart": description,
                // Optionally send the form details in HTML
                "HTMLPart": """
                  <h3>Feedback from \(name.isEmpty ? "Anonymous" : name)</h3>
                  <p><strong>Email:</strong> \(email.isEmpty ? "—" : email)</p>
                  <p><strong>Phone:</strong> \(phone.isEmpty ? "—" : phone)</p>
                  <p><strong>Subject:</strong> \(subject)</p>
                  <p>\(description)</p>
                  """
            ]]
        ]

        // Prepare request
        var request = URLRequest(url: URL(string: "https://api.mailjet.com/v3.1/send")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Basic Auth header
        let authString = "\(mailjetPublicKey):\(mailjetPrivateKey)"
        if let authData = authString.data(using: .utf8)?.base64EncodedString() {
            request.setValue("Basic \(authData)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: mjPayload)

        URLSession.shared.dataTask(with: request) { data, resp, err in
            DispatchQueue.main.async {
                isLoading = false

                if let err = err {
                    errorMessage = "Network error: \(err.localizedDescription)"
                    return
                }

                guard let http = resp as? HTTPURLResponse else {
                    errorMessage = "Invalid response from server"
                    return
                }

                let body = String(data: data ?? Data(), encoding: .utf8) ?? "(empty body)"

                if (200..<300).contains(http.statusCode) {
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder),
                        to: nil, from: nil, for: nil
                    )
                    isSubmitted = true
                    // reset form
                    name = ""; email = ""; phone = ""; subject = ""; description = ""
                } else {
                    errorMessage = "Mailjet error [\(http.statusCode)]: \(body)"
                }
            }
        }
        .resume()
    }
}
