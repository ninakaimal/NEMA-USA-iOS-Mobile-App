//
//  LoginView.swift
//  NEMA USA
//  Created by Nina on 4/12/25.
//  Updated by Sajith on 4/24/25
//  Updated by Arjun on 5/05/25 switch to nemausa.org
//

import SwiftUI
import AuthenticationServices

// MARK: – Notifications
extension Notification.Name {
    static let didReceiveJWT = Notification.Name("didReceiveJWT")
    static let didSessionExpire = Notification.Name("didSessionExpire")
    static let didUpdateBiometricSettings = Notification.Name("didUpdateBiometricSettings")
    static let didUserLogout = Notification.Name("didUserLogout")
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
    
    // FaceID additions - minimal state
    @State private var biometricType: BiometricType = .none
    @State private var canUseBiometric = false
    @State private var showBiometricSetupAlert = false
    // 1. ADD a state variable to track biometric preferences changes
    @State private var biometricEnabled = false
    @State private var justLoggedOut = false
    
    var body: some View {
        NavigationView {
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
                        .textContentType(.emailAddress)
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
                        .textContentType(.password)
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
/*
                    // ► inline error (falls back when .alert() doesn't fire)
                    if showAlert {
                        Text(alertMessage)
                            .font(.subheadline)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
  */
                    // MARK: FaceID Button
                    if canUseBiometric && biometricEnabled {
                        HStack {
                            Rectangle()
                                .frame(height: 1)
                                .foregroundColor(.gray.opacity(0.3))
                            Text("or")
                                .foregroundColor(.gray)
                                .padding(.horizontal, 16)
                            Rectangle()
                                .frame(height: 1)
                                .foregroundColor(.gray.opacity(0.3))
                        }
                        .padding(.horizontal)
                        
                        Button(action: performBiometricLogin) {
                            HStack {
                                Image(systemName: biometricType.iconName)
                                    .font(.system(size: 20))
                                Text("Login with \(biometricType.displayName)")
                                    .fontWeight(.semibold)
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color.orange)
                            .cornerRadius(10)
                        }
                        .padding(.horizontal)
                        .disabled(isLoading)
                    }
                    
                    // ► inline error (unchanged)
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
            .navigationBarHidden(true) // Hide the navigation bar for clean look
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .onAppear {
            // Check biometric availability
            checkBiometricAvailability()
            refreshBiometricState()
            print("🔍 [LoginView] onAppear - canUseBiometric: \(canUseBiometric), biometricEnabled: \(biometricEnabled), justLoggedOut: \(justLoggedOut)")
            
            // FIXED: Don't auto-login if user just logged out
            if canUseBiometric && biometricEnabled && !justLoggedOut {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    print("🔍 [LoginView] Attempting auto biometric login")
                    performBiometricLogin()
                }
            } else if justLoggedOut {
                print("🔍 [LoginView] Skipping auto-login because user just logged out")
                // Reset the flag after one cycle
                justLoggedOut = false
            }
        }
        .alert(isPresented: $showAlert) {
            Alert(
                title:   Text(alertTitle),
                message: Text(alertMessage),
                dismissButton: .default(Text("OK"))
            )
        }
        // NEW: FaceID setup alert
        .alert("Enable \(biometricType.displayName) Login?", isPresented: $showBiometricSetupAlert) {
            Button("Enable") {
                enableBiometricLogin()
                presentationMode.wrappedValue.dismiss() // Dismiss after enabling
            }
            Button("Not Now", role: .cancel) {
                DatabaseManager.shared.disableBiometricAuth()
                presentationMode.wrappedValue.dismiss() // Dismiss after declining
            }
        } message: {
            Text("Use \(biometricType.displayName) to quickly and securely log into your NEMA account.")
        }
        .onReceive(NotificationCenter.default.publisher(for: .didReceiveJWT)) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                refreshBiometricState()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .didUpdateBiometricSettings)) { _ in
            DispatchQueue.main.async {
                refreshBiometricState()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .didUserLogout)) { _ in
            DispatchQueue.main.async {
                print("🔍 [LoginView] Received logout notification, setting justLoggedOut = true")
                justLoggedOut = true
                refreshBiometricState()
            }
        }
    }
    
    // Method to refresh biometric state
    private func refreshBiometricState() {
        biometricEnabled = DatabaseManager.shared.biometricPreferences.isEnabled
        print("🔍 [LoginView] refreshBiometricState - biometricEnabled: \(biometricEnabled)")
    }
    
    // NEW: FaceID methods only - no changes to existing performLogin
    private func checkBiometricAvailability() {
        biometricType = BiometricAuthManager.shared.getBiometricType()
        canUseBiometric = BiometricAuthManager.shared.isBiometricAvailable() &&
                         BiometricAuthManager.shared.isBiometricEnrolled()
        print("🔍 [DEBUG] checkBiometricAvailability - canUseBiometric: \(canUseBiometric), biometricType: \(biometricType)")
    }
    
    private func performBiometricLogin() {
        guard canUseBiometric else { return }
        
        guard let credentials = KeychainManager.shared.getCredentials() else {
            DatabaseManager.shared.disableBiometricAuth()
            return
        }
        
        isLoading = true
        
        Task {
            let result = await BiometricAuthManager.shared.authenticate(
                reason: "Log in to your NEMA account"
            )
            
            await MainActor.run {
                switch result {
                case .success:
                    email = credentials.email
                    password = credentials.password
                    performLogin() // Call your existing method
                    
                case .failure(let error):
                    isLoading = false
                    handleBiometricError(error)
                }
            }
        }
    }
    
    private func handleBiometricError(_ error: BiometricError) {
        switch error {
        case .cancelled:
            break // Just show manual form
        case .lockout:
            alertTitle = "Authentication Locked"
            alertMessage = "Too many failed attempts. Please try again later or use your password."
            showAlert = true
        case .failed:
            alertTitle = "Authentication Failed"
            alertMessage = "Please try again or use your password to log in."
            showAlert = true
        case .notAvailable, .notEnrolled:
            DatabaseManager.shared.disableBiometricAuth()
        case .unknown(let message):
            alertTitle = "Authentication Error"
            alertMessage = message
            showAlert = true
        }
    }
    
    private func enableBiometricLogin() {
        // Credentials should already be saved from saveCredentialsIfNeeded
        if KeychainManager.shared.hasCredentials() {
            DatabaseManager.shared.enableBiometricAuth()
            print("✅ [LoginView] Biometric auth enabled after manual login")
        } else {
            // Fallback: save credentials now if they weren't saved before
            if KeychainManager.shared.saveCredentials(email: email, password: password) {
                DatabaseManager.shared.enableBiometricAuth()
                print("✅ [LoginView] Biometric auth enabled with fresh credential save")
            } else {
                print("❌ [LoginView] Failed to save credentials for biometric auth")
            }
        }
    }
    
    private func promptForBiometricSetup() {
        if DatabaseManager.shared.shouldAskForBiometricSetup() && canUseBiometric {
            showBiometricSetupAlert = true
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
        //print("🔄 [LoginView] Starting login for email: \(email)")
        
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
                                print("🔐 [LoginView] got JWT")
                                DatabaseManager.shared.saveJwtApiToken(jwt)
                                NotificationCenter.default.post(name: .didReceiveJWT, object: nil)
                                
                                // Store the token
                                self.authToken = laravelToken
                                
                                // FIXED: Save credentials BEFORE posting JWT notification
                                self.saveCredentialsIfNeeded()
                                
                                // REMOVED: All biometric setup logic - let the main app handle it via JWT notification
                                // Just dismiss the login view
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
 
    private func debugBiometricSetup() {
        print("🔍 [DEBUG] === Biometric Setup Debug ===")
        print("🔍 [DEBUG] canUseBiometric: \(canUseBiometric)")
        print("🔍 [DEBUG] biometricType: \(biometricType)")
        print("🔍 [DEBUG] isBiometricAvailable: \(BiometricAuthManager.shared.isBiometricAvailable())")
        print("🔍 [DEBUG] isBiometricEnrolled: \(BiometricAuthManager.shared.isBiometricEnrolled())")
        print("🔍 [DEBUG] shouldAskForBiometricSetup: \(DatabaseManager.shared.shouldAskForBiometricSetup())")
        print("🔍 [DEBUG] biometricPreferences: \(DatabaseManager.shared.biometricPreferences)")
        print("🔍 [DEBUG] === End Debug ===")
    }
    
    // 2. UPDATE saveCredentialsIfNeeded to always save (remove hasCredentials check):
    private func saveCredentialsIfNeeded() {
        if canUseBiometric {
            let success = KeychainManager.shared.saveCredentials(email: email, password: password)
            print("🔍 [DEBUG] Saved credentials for potential biometric use: \(success)")
        }
    }
}

struct LoginView_Previews: PreviewProvider {
    static var previews: some View {
        LoginView()
    }
} // end of file
