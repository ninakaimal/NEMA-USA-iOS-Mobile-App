import SwiftUI
import UIKit

struct ContactView: View {
    @State private var name        = ""
    @State private var email       = ""
    @State private var phone       = ""
    @State private var subject     = ""
    @State private var description = ""
    @State private var isSubmitted = false
    @State private var isLoading   = false
    @State private var errorMessage = ""

    var body: some View {
        ZStack(alignment: .top) {
            Color.orange
                .ignoresSafeArea(edges: .top)
                .frame(height: 56)

            VStack(spacing: 0) {
                BannerView()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Send Feedback")
                            .font(.title2).bold()
                            .foregroundColor(.primary)    // restored
                            .padding(.top, 16)

                        Text("We'd love to hear from you! Please fill out the form below.")
                            .font(.subheadline)
                            .foregroundColor(.gray)       // helper

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
                                .foregroundColor(.primary) // restored
                            TextEditor(text: $description)
                                .frame(height: 55)
                                .padding(10)
                               // .background(Color.white)
                                .background(Color(.systemBackground))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
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
                }
            }
        }
        //.background(Color.white)
        .background(Color(.systemBackground))
        .accentColor(.primary)   // override white accent
    }

    private func submitForm() { /* your logic */ }
}
