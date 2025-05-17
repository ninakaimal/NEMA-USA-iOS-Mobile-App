//
//  RegistrationView.swift
//  NEMA USA
//  Created by Nina on 4/24/25.
//
import SwiftUI

struct RegistrationView: View {
    @Environment(\.presentationMode) private var presentationMode
    @AppStorage("apiAuthToken") private var apiToken: String?
    
    // MARK: – Form state
    @State private var name            = ""
    @State private var phone           = ""
    @State private var email           = ""
    @State private var confirmEmail    = ""
    @State private var password        = ""
    @State private var confirmPassword = ""
    @State private var address         = ""
    @State private var spouseName      = ""
    @State private var spouseEmail     = ""
    
    // Optional membership selection
    @State private var membershipOptions: [MobileMembershipPackage] = []
    @State private var selectedPackageIndex = 0
    @State private var wantsMembership = false
    
    @State private var showAlert     = false
    @State private var alertTitle    = ""
    @State private var alertMessage  = ""
    @State private var isSubmitting  = false
    
    @State private var emailTouched = false
    @State private var confirmEmailTouched = false
    @State private var confirmPasswordTouched = false
    
    private var nameField: some View {
        VStack(alignment: .leading) {
            TextField("Name", text: $name)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .padding(10)
                .background(Color(.systemBackground))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.orange, lineWidth: 0.5))
                .padding(.horizontal)
            if !nameValid {
                Text("Full Name is required")
                    .foregroundColor(.orange).font(.caption).padding(.horizontal)
            }
        }
    }

    private var phoneField: some View {
        VStack(alignment: .leading) {
            TextField("Phone", text: $phone)
                .keyboardType(.phonePad)
                .padding(10)
                .background(Color(.systemBackground))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.orange, lineWidth: 0.5))
                .padding(.horizontal)
            if !phoneValid {
                Text("Phone number is required")
                    .foregroundColor(.orange).font(.caption).padding(.horizontal)
            }
        }
    }

    private var emailField: some View {
        VStack(alignment: .leading) {
            TextField("Email, use as your login", text: $email, onEditingChanged: { editing in
                if !editing { self.emailTouched = true }
            })
            .keyboardType(.emailAddress)
            .autocapitalization(.none)
            .disableAutocorrection(true)
            .padding(10)
            .background(Color(.systemBackground))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.orange, lineWidth: 0.5))
            .padding(.horizontal)

            if emailTouched && !emailValid {
                Text("Invalid email format")
                    .foregroundColor(.orange).font(.caption).padding(.horizontal)
            }
        }
    }

    private var confirmEmailField: some View {
        VStack(alignment: .leading) {
            TextField("Confirm Email", text: $confirmEmail, onEditingChanged: { editing in
                if !editing { self.confirmEmailTouched = true }
            })
            .keyboardType(.emailAddress)
            .autocapitalization(.none)
            .disableAutocorrection(true)
            .padding(10)
            .background(Color(.systemBackground))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.orange, lineWidth: 0.5))
            .padding(.horizontal)

            if confirmEmailTouched && !emailMatch {
                Text("Emails do not match")
                    .foregroundColor(.orange).font(.caption).padding(.horizontal)
            }
        }
    }

    private var passwordField: some View {
        VStack(alignment: .leading) {
            SecureField("Password", text: $password)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .padding(10)
                .background(Color(.systemBackground))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.orange, lineWidth: 0.5))
                .padding(.horizontal)

            if !passwordValid {
                Text("Password must be at least 8 characters long with a number, lower and uppercase letters")
                    .foregroundColor(.orange).font(.caption).padding(.horizontal)
            }
        }
    }

    private var confirmPasswordField: some View {
        VStack(alignment: .leading) {
            SecureField("Confirm Password", text: $confirmPassword)
                .onChange(of: confirmPassword) { _ in
                    self.confirmPasswordTouched = true
                }
            .autocapitalization(.none)
            .disableAutocorrection(true)
            .padding(10)
            .background(Color(.systemBackground))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.orange, lineWidth: 0.5))
            .padding(.horizontal)

            if confirmPasswordTouched && !passwordMatch {
                Text("Passwords do not match")
                    .foregroundColor(.orange).font(.caption).padding(.horizontal)
            }
        }
    }

    private var addressField: some View {
        VStack(alignment: .leading) {
            TextField("Address", text: $address)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .padding(10)
                .background(Color(.systemBackground))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.orange, lineWidth: 0.5))
                .padding(.horizontal)

            if !addressValid {
                Text("Address is required")
                    .foregroundColor(.orange).font(.caption).padding(.horizontal)
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("Create Your Account")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.orange)
                    .padding(.bottom, 10)
                
                // MARK: – Required fields
                Group {
                    nameField
                    phoneField
                    emailField
                    confirmEmailField
                    passwordField
                    confirmPasswordField
                    addressField
                }
                // MARK: – Spouse info (optional)
                Group {
                    TextField("Spouse Name", text: $spouseName)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .padding(10)
                        .background(Color(.systemBackground))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.orange, lineWidth: 0.5))
                        .padding(.horizontal)
                    
                    TextField("Spouse Email", text: $spouseEmail)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .padding(10)
                        .background(Color(.systemBackground))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.orange, lineWidth: 0.5))
                        .padding(.horizontal)
                }
                
                //        // MARK: – Membership toggle
                //        Toggle("Join NEMA as a member", isOn: $wantsMembership)
                //          .toggleStyle(SwitchToggleStyle(tint: .orange))
                
                //        // MARK: – Membership options
                //        if wantsMembership {
                //          if membershipOptions.isEmpty {
                //            ProgressView("Loading options…")
                //          } else {
                //            Picker("", selection: $selectedPackageIndex) {
                //              ForEach(membershipOptions.indices, id: \.self) { idx in
                //                let pkg = membershipOptions[idx]
                //                Text("\(pkg.years_of_validity)-year $\(Int(pkg.amount))")
                //                  .tag(idx)
                //              }
                //            }
                //            .pickerStyle(SegmentedPickerStyle())
                //            .padding(.vertical)
                //          }
                //        }
                
                // MARK: – Informational text
                VStack(alignment: .leading, spacing: 4) {
                    Text("An account is required for registering for competitions such as Drishya and will help you track your registrations.")
                        .fixedSize(horizontal: false, vertical: true)
                    Text("  ")
                    Text("In addition, you can join as a NEMA member from the account screen after you register by paying annual fees to get the following benefits:")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("• Discount to NEMA ticketed events (Onam, Christmas, etc)")
                        Text("• Priority registrations for NEMA Sports events")
                        Text("• All members who join before Jun 15th of the current year can nominate members for NEMA BOD, vote in NEMA elections and get nominated to BOD")
                        Text("• Year-round opportunity to connect with Malayalee community in New England area and build life-long friendships for you and your family.")
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.vertical, 8)
                
                // MARK: – Register button
                Button(action: submit) {
                    HStack {
                        Spacer()
                        if isSubmitting {
                            ProgressView().tint(.white)
                        } else {
                            Text("Register").bold().foregroundColor(.white)
                        }
                        Spacer()
                    }
                    .padding()
                    .background(isFormValid ? Color.orange : Color.gray)
                    .cornerRadius(8)
                }
                .disabled(!isFormValid || isSubmitting)
            }
            .padding()
        }
        .navigationTitle("Sign Up")
        .alert(isPresented: $showAlert) {
            Alert(title: Text(alertTitle), message: Text(alertMessage), dismissButton: .default(Text("OK")) {
                if alertTitle == "Registration Successful" {
                    presentationMode.wrappedValue.dismiss()
                }
            }
            
            )
        }
      //  .onAppear(perform: loadPackages) no longer adding membership
    }
    
    // MARK: – Email format validation
    private var isValidEmail: Bool {
        let pattern = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}"
        return NSPredicate(format: "SELF MATCHES %@", pattern).evaluate(with: email)
    }
    
    // MARK: – Form validation
    
    private var nameValid: Bool { !name.isEmpty }
    private var phoneValid: Bool { !phone.isEmpty }
    private var emailValid: Bool { isValidEmail }
    private var emailMatch: Bool { email == confirmEmail && !confirmEmail.isEmpty }
    private var passwordValid: Bool { !password.isEmpty && password.count >= 6 }
    private var passwordMatch: Bool { password == confirmPassword && !confirmPassword.isEmpty }
    private var addressValid: Bool { !address.isEmpty }
    
    private var isFormValid: Bool {
        nameValid && phoneValid && emailValid && emailMatch && passwordValid && passwordMatch && addressValid
    }
    
    private func loadPackages() {
        NetworkManager.shared.fetchMembershipPackages { result in
            if case .success(let packs) = result {
                membershipOptions = packs
            }
        }
    }
    
    private func submit() {
        guard isFormValid else {
            isSubmitting = false
            alertTitle = "Validation Error"
            alertMessage = "Please correct highlighted errors before submitting."
            showAlert = true
            return
        }
        isSubmitting = true
        let token = UUID().uuidString
        let selectedMembershipId = wantsMembership ? "\(membershipOptions[selectedPackageIndex].id)" : "0"
        
        NetworkManager.shared.register(
            name: name,
            phone: phone,
            email: email,
            confirmEmail: confirmEmail,
            password: password,
            confirmPassword: confirmPassword,
            dateOfBirth: "",
            address: address,
            spouseName: spouseName.isEmpty ? nil : spouseName,
            spouseEmail: spouseEmail.isEmpty ? nil : spouseEmail,
            spouseDob: nil,
            joinAsMember: wantsMembership,
            selectedMembershipId: selectedMembershipId,
            captchaToken: token
        ) { result in
            DispatchQueue.main.async {
                isSubmitting = false
                switch result {
                case .success((let t, _)):
                    apiToken = t
                    UserDefaults.standard.removeObject(forKey: "membershipExpiryDate")
                    alertTitle = "Registration Successful"
                    alertMessage = "Welcome to NEMA! Your account has been created successfully."
                    showAlert = true
                case .failure(let err):
                    alertTitle = "Registration Failed. Please try again or contact NEMA."
                    alertMessage = err.localizedDescription
                    showAlert = true
                }
            }
        }
    }
}
