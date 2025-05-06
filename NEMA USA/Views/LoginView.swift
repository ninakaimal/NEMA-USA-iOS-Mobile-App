//
//  LoginView.swift
//  NEMA USA
//  Created by Nina on 4/12/25.
//  Updated by Sajith on 4/24/25
//  Updated by Arjun on 5/05/25 switch to nemausa.org
//

import SwiftUI

struct LoginView: View {
    @Environment(\.presentationMode) private var presentationMode

    /// where we store the Laravel scraping session token
    @AppStorage("laravelSessionToken") private var authToken: String?

    @State private var email        = ""
    @State private var password     = ""
    @State private var isLoading    = false
    @State private var showAlert    = false
    @State private var alertTitle   = ""
    @State private var alertMessage = ""

    // Logo animation state
    @State private var logoScale      : CGFloat = 1.4
    @State private var logoTopPadding : CGFloat = 200
    @State private var logoOpacity    : Double  = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // MARK: Logo
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

                // MARK: Titles
                Text("NEW ENGLAND MALAYALEE ASSOCIATION")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.orange)
                    .multilineTextAlignment(.center)

                Text("ന്യൂ ഇംഗ്ലണ്ട് മലയാളി അസോസിയേഷൻ‍")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.orange)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 40)

                // MARK: Email Field
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
                    .overlay(RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.orange, lineWidth: 0.5))
                    .padding(.horizontal)

                // MARK: Password Field
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
                    .overlay(RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.orange, lineWidth: 0.5))
                    .padding(.horizontal)

                // MARK: Login Button
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

                // MARK: Footer
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
                title:   Text(alertTitle),
                message: Text(alertMessage),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private func performLogin() {
        // 0) Validate
        guard !email.isEmpty, !password.isEmpty else {
            alertTitle   = "Missing Info"
            alertMessage = "Please enter both email and password."
            showAlert    = true
            return
        }

        // 1) Start spinner
        isLoading = true
        print("🔄 [LoginView] Starting login for email: \(email)")

        // 2) Scrape Laravel login → get session + profile
        NetworkManager.shared.login(email: email, password: password) { scrapeResult in
            switch scrapeResult {
            case let .success((laravelToken, user)):
                print("✅ [LoginView] Laravel scrape succeeded, token: \(laravelToken)")
                print("ℹ️ [LoginView] User profile: \(user)")

                // 2a) Save scraped profile & session
                DatabaseManager.shared.saveUser(user)
                DatabaseManager.shared.saveLaravelSessionToken(laravelToken)
                authToken = laravelToken
                print("💾 [LoginView] Stored laravelSessionToken in AppStorage")

                // 3) Fetch JSON-API JWT
                NetworkManager.shared.loginJSON(email: email, password: password) { jwtResult in
                    DispatchQueue.main.async {
                        // stop spinner
                        isLoading = false

                        switch jwtResult {
                        case let .success((jwt, _)):
                            print("🔐 [LoginView] got JWT = \(jwt)")
                            DatabaseManager.shared.saveJwtApiToken(jwt)
                        case let .failure(err):
                            print("⚠️ [LoginView] Couldn't fetch JSON-API token:", err)
                        }

                        // 4) Finally dismiss the login sheet
                        print("🚪 [LoginView] Dismissing login sheet")
                        presentationMode.wrappedValue.dismiss()
                    }
                }

            case let .failure(error):
                DispatchQueue.main.async {
                    // stop spinner & report
                    isLoading = false
                    let msg: String
                    switch error {
                    case .serverError(let m):
                        msg = m
                        print("❌ [LoginView] serverError:", m)
                    case .invalidResponse:
                        msg = "Server error—please try again."
                        print("❌ [LoginView] invalidResponse")
                    case .decodingError:
                        msg = "Bad data from server."
                        print("❌ [LoginView] decodingError:", error)
                    }
                    alertTitle   = "Login Failed"
                    alertMessage = msg
                    showAlert    = true
                }
            }
        }
    }
}

struct LoginView_Previews: PreviewProvider {
    static var previews: some View {
        LoginView()
    }
}
