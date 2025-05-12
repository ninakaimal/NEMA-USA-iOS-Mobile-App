import SwiftUI

enum PasswordResetMode {
    case requestLink
    case reset(token: String)
}

struct PasswordResetView: View {
    @Environment(\EnvironmentValues.dismiss) private var dismiss

    let mode: PasswordResetMode

    @State private var email = ""
    @State private var newPassword = ""
    @State private var confirmNewPassword = ""

    @State private var isLoading = false
    @State private var showAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""

    @State private var logoScale: CGFloat = 1.4
    @State private var logoOpacity: Double = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image("LaunchLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120, height: 120)
                    .scaleEffect(logoScale)
                    .opacity(logoOpacity)
                    .padding(.top, 40)
                    .onAppear {
                        withAnimation(.easeOut(duration: 1.0)) {
                            logoScale = 1.0
                            logoOpacity = 1.0
                        }
                    }

                Text(viewTitle)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.orange)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 30)

                if case .requestLink = mode {
                    TextField("Enter your email", text: $email)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .padding(12)
                        .background(Color.white)
                        .overlay(RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.orange, lineWidth: 0.5))
                        .padding(.horizontal)

                    Button(action: requestResetLink) {
                        HStack {
                            Spacer()
                            if isLoading {
                                ProgressView().tint(.white)
                            } else {
                                Text("Send Reset Link")
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
                    .disabled(email.isEmpty || isLoading)
                }

                if case .reset(_) = mode {
                    SecureField("New Password", text: $newPassword)
                        .padding(12)
                        .background(Color.white)
                        .overlay(RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.orange, lineWidth: 0.5))
                        .padding(.horizontal)

                    SecureField("Confirm Password", text: $confirmNewPassword)
                        .padding(12)
                        .background(Color.white)
                        .overlay(RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.orange, lineWidth: 0.5))
                        .padding(.horizontal)

                    passwordRequirementsView

                    Button(action: resetPassword) {
                        HStack {
                            Spacer()
                            if isLoading {
                                ProgressView().tint(.white)
                            } else {
                                Text("Reset Password")
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
                    .disabled(!isPasswordValid || isLoading)
                }

                Spacer()

                Text("© NEMA Boston, All rights reserved.")
                    .font(.footnote)
                    .foregroundColor(.gray.opacity(0.7))
                    .padding(.top, 30)
            }
        }
        .background(Color(.systemBackground))
        .alert(alertTitle, isPresented: $showAlert) {
            Button("OK") {
                if alertTitle == "Success" {
                    dismiss()
                }
            }
        } message: {
            Text(alertMessage)
        }
    }

    private var viewTitle: String {
        switch mode {
        case .requestLink: return "Forgot Your Password?"
        case .reset: return "Create New Password"
        }
    }

    private var isPasswordValid: Bool {
        newPassword == confirmNewPassword &&
        newPassword.count >= 8 &&
        newPassword.rangeOfCharacter(from: .uppercaseLetters) != nil &&
        newPassword.rangeOfCharacter(from: .lowercaseLetters) != nil &&
        newPassword.rangeOfCharacter(from: .decimalDigits) != nil
    }

    private var passwordRequirementsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Password must contain:").bold()

            Label("At least one lowercase letter", systemImage: newPassword.rangeOfCharacter(from: .lowercaseLetters) != nil ? "checkmark.circle" : "xmark.circle")
            Label("At least one capital letter", systemImage: newPassword.rangeOfCharacter(from: .uppercaseLetters) != nil ? "checkmark.circle" : "xmark.circle")
            Label("At least one number", systemImage: newPassword.rangeOfCharacter(from: .decimalDigits) != nil ? "checkmark.circle" : "xmark.circle")
            Label("Minimum 8 characters", systemImage: newPassword.count >= 8 ? "checkmark.circle" : "xmark.circle")
        }
        .foregroundColor(.gray)
        .font(.footnote)
        .padding(.vertical)
        .padding(.horizontal)
    }

    private func requestResetLink() {
        isLoading = true
        NetworkManager.shared.sendPasswordResetLink(email: email) { result in
            isLoading = false
            switch result {
            case .success(let msg):
                alertTitle = "Success"
                alertMessage = msg
            case .failure(let err):
                alertTitle = "Error"
                alertMessage = err.localizedDescription
            }
            showAlert = true
        }
    }

    private func resetPassword() {
        guard case let .reset(token) = mode else { return }
        isLoading = true
        NetworkManager.shared.resetPassword(token: token, newPassword: newPassword) { result in
            isLoading = false
            switch result {
            case .success(let msg):
                alertTitle = "Success"
                alertMessage = msg
            case .failure(let err):
                alertTitle = "Error"
                alertMessage = err.localizedDescription
            }
            showAlert = true
        }
    }
}

struct PasswordResetView_Previews: PreviewProvider {
    static var previews: some View {
        PasswordResetView(mode: .requestLink)
    }
}
