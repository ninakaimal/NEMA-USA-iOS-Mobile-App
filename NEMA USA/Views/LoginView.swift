//
//  LoginView.swift
//  NEMA USA
//  Created by Nina on 4/12/25.
//  Updated by Sajith on 4/21/25
//

import SwiftUI

struct LoginView: View {
    // This is the same key AccountView watches
    @AppStorage("authToken") private var authToken: String?

    @State private var email        = ""
    @State private var password     = ""
    @State private var isLoading    = false
    @State private var showAlert    = false
    @State private var alertTitle   = ""
    @State private var alertMessage = ""

    // Logo animation
    @State private var logoScale      : CGFloat = 1.4
    @State private var logoTopPadding : CGFloat = 200
    @State private var logoOpacity    : Double  = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // MARK: – Logo
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

                // MARK: – Titles
                Text("NEW ENGLAND MALAYALEE ASSOCIATION")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.orange)
                    .multilineTextAlignment(.center)

                Text("ന്യൂ ഇംഗ്ലണ്ട് മലയാളി അസോസിയേഷൻ‍")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.orange)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 40)

                // MARK: – Email Field
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

                // MARK: – Password Field
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

                // MARK: – Login Button
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

                // MARK: – Footer
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
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private func performLogin() {
        guard !email.isEmpty, !password.isEmpty else {
            alertTitle   = "Missing Info"
            alertMessage = "Please enter both email and password."
            showAlert    = true
            return
        }

        isLoading = true

        NetworkManager.shared.login(email: email, password: password) { result in
            DispatchQueue.main.async { isLoading = false }

            switch result {
            case let .success((token, user)):
                // 1) Persist full profile + token
                DatabaseManager.shared.saveUser(user)
                DatabaseManager.shared.saveToken(token)

                // 2) ALSO update the @AppStorage binding
                authToken = token

                // 3) Success alert
                alertTitle   = "Welcome, \(user.name)!"
                alertMessage = "You have successfully logged in."
                showAlert    = true

                // 4) Clear form
                email    = ""
                password = ""

            case let .failure(error):
                alertTitle = "Login Failed"
                alertMessage = {
                    switch error {
                    case .invalidResponse:     return "Server error—please try again."
                    case .serverError(let msg): return msg
                    case .decodingError:       return "Bad data from server."
                    }
                }()
                showAlert = true
            }
        }
    }
}
