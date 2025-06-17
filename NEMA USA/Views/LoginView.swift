//
//  LoginView.swift
//  NEMA USA
//  Created by Nina on 4/12/25.
//  Updated by Sajith on 4/24/25
//  Updated by Arjun on 5/05/25 switch to nemausa.org
//

import SwiftUI

// MARK: – Notifications
extension Notification.Name {
  /// Fired as soon as we’ve stored the JSON-API JWT
  static let didReceiveJWT = Notification.Name("didReceiveJWT")

    /// Fired whenever our token refresh fails → session expired
    static let didSessionExpire = Notification.Name("didSessionExpire")
}
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
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            withAnimation(.easeOut(duration: 0.7)) {
                                logoScale      = 1.0
                                logoTopPadding = 40
                                logoOpacity    = 1.0
                            }
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
                TextField("Email", text: $email)
                    .foregroundColor(email.isEmpty ? .orange.opacity(0.5) : .primary)
                            .padding(.leading, 6)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .padding(12)
                    .background(Color(.systemBackground))
                    .overlay(RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.orange, lineWidth: 0.5))
                    .padding(.horizontal)
                
                // MARK: Password Field
                
            SecureField("Password", text: $password)
                .foregroundColor(email.isEmpty ? .orange.opacity(0.5) : .primary)
                            .padding(.leading, 6)
                    .disableAutocorrection(true)
                    .autocapitalization(.none)
                    .padding(12)
                    .background(Color(.systemBackground))
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
                // ► inline error (falls back when .alert() doesn’t fire)
                if showAlert {
                    Text(alertMessage)
                        .font(.subheadline)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                // MARK: Forgot password
                        HStack(spacing: 30) {
                        NavigationLink("Create an Account", destination: RegistrationView())
                        NavigationLink("Forgot Password?", destination: PasswordResetView(mode: .requestLink))
                        }
                        .font(.subheadline)
                        .foregroundColor(.orange)
                        .padding(.top, 24)
                
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
            DispatchQueue.main.async {
                switch scrapeResult {
                case let .success((laravelToken, _)):
                    DatabaseManager.shared.saveLaravelSessionToken(laravelToken)
                    print("💾 [LoginView] Stored laravelSessionToken")
                    
                    // Now perform JSON API login after Laravel success
                    NetworkManager.shared.loginJSON(email: self.email, password: self.password) { jwtResult in
                        DispatchQueue.main.async {
                            // stop spinner for JWT step
                            self.isLoading = false
                            switch jwtResult {
                            case let .success((jwt, _)):
                                //print("🔐 [LoginView] got JWT = \(jwt)")
                                print("🔐 [LoginView] got JWT")
                                DatabaseManager.shared.saveJwtApiToken(jwt)
                                NotificationCenter.default.post(name: .didReceiveJWT, object: nil)
                                // only now set authToken & dismiss
                                self.authToken = laravelToken
                                self.presentationMode.wrappedValue.dismiss()
                                
                            case let .failure(err):
                                self.alertTitle = "Login Failed"
                                switch err {
                                case .invalidResponse:
                                    self.alertMessage = "Invalid email or password. Please try again."
                                case .serverError(let m):
                                    self.alertMessage = m
                                case .decodingError:
                                    self.alertMessage = "Unexpected response from server."
                                }
                                self.showAlert = true
                            }
                        }
                    }
                    
                case let .failure(error):
                    self.isLoading = false
                    self.alertTitle = "Login Failed"
                    switch error {
                    case .invalidResponse:
                        self.alertMessage = "Invalid email or password. Please try again."
                    case .serverError(let m):
                        self.alertMessage = m
                    case .decodingError:
                        self.alertMessage = "Bad data from server."
                    }
                    self.showAlert = true
                }
            }
        }
    }
}
struct LoginView_Previews: PreviewProvider {
    static var previews: some View {
        LoginView()
    }
} // end of file
