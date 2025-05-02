// LoginView.swift
// NEMA USA
// Created by Nina on 4/12/25.
// Updated by Sajith on 4/24/25

import SwiftUI

struct LoginView: View {
    @AppStorage("authToken") private var authToken: String?

    @State private var email        = ""
    @State private var password     = ""
    @State private var isLoading    = false
    @State private var showAlert    = false
    @State private var alertTitle   = ""
    @State private var alertMessage = ""

    // Hold onto a successful login until the user taps OK
    @State private var pendingLogin: (token: String, user: UserProfile)?

    // Logo animation
    @State private var logoScale      : CGFloat = 1.4
    @State private var logoTopPadding : CGFloat = 200
    @State private var logoOpacity    : Double  = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Logo
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

                // Titles
                Text("NEW ENGLAND MALAYALEE ASSOCIATION")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.orange)
                    .multilineTextAlignment(.center)

                Text("ന്യൂ ഇംഗ്ലണ്ട് മലയാളി അസോസിയേഷൻ‍")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.orange)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 40)

                // Email Field
                TextField("", text: $email)
                    .placeholder(when: email.isEmpty) {
                        Text("Email")
                            .foregroundColor(.orange.opacity(0.2))
                            .padding(.leading, 6)
                    }
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .padding(12)
                    .background(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.orange, lineWidth: 0.5)
                    )
                    .padding(.horizontal)

                // Password Field
                SecureField("", text: $password)
                    .placeholder(when: password.isEmpty) {
                        Text("Password")
                            .foregroundColor(.orange.opacity(0.2))
                            .padding(.leading, 6)
                    }
                    .disableAutocorrection(true)
                    .autocapitalization(.none)
                    .padding(12)
                    .background(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.orange, lineWidth: 0.5)
                    )
                    .padding(.horizontal)

                // Login Button
                Button(action: performLogin) {
                    HStack {
                        Spacer()
                        if isLoading {
                            ProgressView()
                        } else {
                            Text("Login")
                                .foregroundColor(.white)
                                .bold()
                        }
                        Spacer()
                    }
                    .padding(12)
                    .background(Color.orange)
                    .cornerRadius(10)
                }
                .padding(.horizontal)
                .disabled(isLoading)

                // Footer
                Text("© NEMA Boston, All rights reserved.")
                    .font(.footnote)
                    .foregroundColor(.gray.opacity(0.7))
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
                dismissButton: .default(Text("OK")) {
                    // Only commit on success
                    if let login = pendingLogin {
                        DatabaseManager.shared.saveUser(login.user)
                        DatabaseManager.shared.saveToken(login.token)
                        authToken = login.token
                        pendingLogin = nil
                    }
                }
            )
        }
    }

    private func performLogin() {
        // 1) Validate inputs
        guard !email.isEmpty, !password.isEmpty else {
            alertTitle   = "Missing Info"
            alertMessage = "Please enter both email and password."
            pendingLogin = nil
            showAlert    = true
            return
        }

        isLoading = true

        // 2) Attempt login
        NetworkManager.shared.login(email: email, password: password) { result in
            DispatchQueue.main.async { isLoading = false }

            switch result {
            case let .success((token, user)):
                // Defer commit until OK
                pendingLogin = (token, user)
                alertTitle   = "Welcome, \(user.name)!"
                alertMessage = "You have successfully logged in."
                showAlert    = true
                // Clear form
                email    = ""
                password = ""

            case let .failure(error):
                pendingLogin = nil
                alertTitle   = "Login Failed"
                alertMessage = {
                    switch error {
                    case .serverError(let msg): return msg
                    case .invalidResponse:       return "Server error—please try again."
                    case .decodingError:         return "Bad data from server."
                    }
                }()
                showAlert = true
            }
        }
    }
}
