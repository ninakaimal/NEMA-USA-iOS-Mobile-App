//
//  LoginView.swift
//  NEMA USA
//  Created by Nina on 4/12/25.
//

import SwiftUI

struct LoginView: View {
    // Bind directly to the same key that DatabaseManager.shared.saveToken writes to
    @AppStorage("authToken") private var authToken: String?

    @State private var email        = ""
    @State private var password     = ""
    @State private var errorMessage = ""
    @State private var isLoading    = false

    // Animation states
    @State private var logoScale: CGFloat     = 1.4
    @State private var logoTopPadding: CGFloat = 200
    @State private var logoOpacity: Double    = 0

    // New state for showing alerts
    @State private var showAlert    = false
    @State private var alertTitle   = ""
    @State private var alertMessage = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Animated logo
                Image("LaunchLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120, height: 120)
                    .scaleEffect(logoScale)
                    .opacity(logoOpacity)
                    .padding(.top, logoTopPadding)
                    .onAppear {
                        withAnimation(.easeOut(duration: 1.0)) {
                            logoScale      = 1.0
                            logoTopPadding = 40
                            logoOpacity    = 1.0
                        }
                    }

                // NEMA Malayalam text
                Text("NEW ENGLAND MALAYALEE ASSOCIATION")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(Color.orange)
                    .multilineTextAlignment(.center)
                    .padding(.top, -10)

                Text("ന്യൂ ഇംഗ്ലണ്ട് മലയാളി അസോസിയേഷൻ‍")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(Color.orange)
                    .multilineTextAlignment(.center)
                    .padding(.top, -10)
                    .padding(.bottom, 40)

                // Email Field
                TextField("", text: $email)
                    .placeholder(when: email.isEmpty) {
                        Text("Email")
                            .foregroundColor(Color.orange.opacity(0.5))
                            .padding(.leading, 6)
                    }
                    .foregroundColor(Color.orange)
                    .tint(Color.orange)
                    .font(.system(size: 15))
                    .padding(12)
                    .background(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.orange, lineWidth: 0.5)
                    )
                    .autocapitalization(.none)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled(true)
                    .textInputAutocapitalization(.never)
                    .padding(.horizontal)

                // Password Field
                SecureField("", text: $password)
                    .placeholder(when: password.isEmpty) {
                        Text("Password")
                            .foregroundColor(Color.orange.opacity(0.5))
                            .padding(.leading, 6)
                    }
                    .foregroundColor(Color.orange)
                    .tint(Color.orange)
                    .font(.system(size: 15))
                    .padding(12)
                    .background(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.orange, lineWidth: 1)
                    )
                    .autocorrectionDisabled(true)
                    .textInputAutocapitalization(.never)
                    .padding(.horizontal)

                // Error Message
                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.caption)
                        .padding(.horizontal)
                }

                // Login Button
                Button(action: login) {
                    HStack {
                        Spacer()
                        if isLoading {
                            ProgressView()
                        } else {
                            Text("Login")
                                .foregroundColor(.white)
                                .bold()
                                .font(.system(size: 16))
                        }
                        Spacer()
                    }
                    .padding(12)
                    .background(Color.orange)
                    .cornerRadius(10)
                }
                .padding(.horizontal)
                .padding(.top, 4)

                // Footer Note
                Text("© NEMA Boston, All rights reserved.")
                    .font(.footnote)
                    .foregroundColor(Color.gray.opacity(0.7))
                    .padding(.top, 30)

                Spacer(minLength: 20)
            }
        }
        .background(Color(.systemBackground))
        .ignoresSafeArea(.keyboard)
        .alert(isPresented: $showAlert) {
            Alert(
                title: Text(alertTitle),
                message: Text(alertMessage),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private func login() {
        guard !email.isEmpty && !password.isEmpty else {
            errorMessage = "Please enter both email and password"
            return
        }

        isLoading    = true
        errorMessage = ""

        guard let url = URL(string: "https://nema-api.kanakaagro.in/api/login") else {
            errorMessage = "Invalid API URL"
            isLoading    = false
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod  = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody   = try? JSONSerialization.data(
            withJSONObject: ["email": email, "password": password]
        )

        URLSession.shared.dataTask(with: request) { data, _, error in
            DispatchQueue.main.async { isLoading = false }

            if let err = error {
                alertTitle   = "Login Failed"
                alertMessage = err.localizedDescription
                showAlert    = true
                return
            }

            guard
                let data = data,
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let token = json["token"] as? String
            else {
                alertTitle   = "Login Failed"
                alertMessage = "Wrong email/password or server error."
                showAlert    = true
                return
            }

            // Success: persist token and show confirmation
            DispatchQueue.main.async {
                DatabaseManager.shared.saveToken(token)
                alertTitle   = "Login Successful"
                alertMessage = "Welcome back!"
                showAlert    = true

                // Clear input fields
                email    = ""
                password = ""
            }
        }
        .resume()
    }
}
