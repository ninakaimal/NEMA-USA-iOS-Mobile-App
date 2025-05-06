//
//  RegistrationView.swift
//  NEMA USA
//  Created by Nina on 4/24/25.
//
// RegistrationView.swift
import SwiftUI

struct RegistrationView: View {
  @Environment(\.presentationMode) private var presentationMode
  @AppStorage("laravelSessionToken") private var authToken: String?

  @State private var name            = ""
  @State private var phone           = ""
  @State private var email           = ""
  @State private var confirmEmail    = ""
  @State private var dateOfBirth     = ""  // “YYYY-MM-DD” or “YYYY-MM”
  @State private var address         = ""
  @State private var spouseName      = ""
  @State private var spouseEmail     = ""
  @State private var spouseDob       = ""
  @State private var password        = ""
  @State private var confirmPassword = ""
  @State private var joinAsMember    = false
  @State private var captchaChecked  = false   // simple stand-in for modern captcha

  @State private var showAlert       = false
  @State private var alertTitle      = ""
  @State private var alertMessage    = ""
  @State private var isSubmitting    = false

  var body: some View {
    ScrollView {
      VStack(spacing: 16) {
        Group {
          TextField("Name *", text: $name)
          TextField("Phone *", text: $phone)
            .keyboardType(.phonePad)
          TextField("Email *", text: $email)
            .keyboardType(.emailAddress)
          TextField("Confirm Email *", text: $confirmEmail)
            .keyboardType(.emailAddress)
          TextField("Birth Month and Year *", text: $dateOfBirth)
            .placeholder(when: dateOfBirth.isEmpty) {
              Text("YYYY-MM or YYYY-MM-DD").foregroundColor(.gray)
            }
          TextField("Address *", text: $address)
        }

        Group {
          TextField("Spouse Name", text: $spouseName)
          TextField("Spouse Email", text: $spouseEmail)
            .keyboardType(.emailAddress)
          TextField("Spouse Birth Month & Year", text: $spouseDob)
            .placeholder(when: spouseDob.isEmpty) {
              Text("YYYY-MM or YYYY-MM-DD").foregroundColor(.gray)
            }
        }

        Group {
          SecureField("Password *", text: $password)
          SecureField("Confirm Password *", text: $confirmPassword)
        }

        // Modern “captcha” stand-in
        Toggle("I’m not a robot", isOn: $captchaChecked)

        Toggle("Join as a NEMA Member", isOn: $joinAsMember)

        Button {
          submit()
        } label: {
          HStack {
            Spacer()
            if isSubmitting {
              ProgressView()
            } else {
              Text("Register")
                .bold()
                .foregroundColor(.white)
            }
            Spacer()
          }
          .padding()
          .background(isFormValid ? Color.orange : Color.gray)
          .cornerRadius(8)
        }
        .disabled(!isFormValid)
      }
      .padding()
    }
    .navigationTitle("Sign Up")
    .alert(isPresented: $showAlert) {
      Alert(title: Text(alertTitle), message: Text(alertMessage), dismissButton: .default(Text("OK")))
    }
  }

  private var isFormValid: Bool {
    // all starred
    guard
      !name.isEmpty,
      !phone.isEmpty,
      !email.isEmpty,
      !confirmEmail.isEmpty,
      !dateOfBirth.isEmpty,
      !address.isEmpty,
      !password.isEmpty,
      !confirmPassword.isEmpty,
      captchaChecked
    else { return false }

    guard email == confirmEmail else { return false }
    guard password == confirmPassword else { return false }
    return true
  }

  private func submit() {
    guard isFormValid else { return }
    isSubmitting = true

    let captchaToken = "dummy-\(UUID().uuidString)"  // replace with real service

    NetworkManager.shared.register(
      name:            name,
      phone:           phone,
      email:           email,
      confirmEmail:    confirmEmail,
      password:        password,
      confirmPassword: confirmPassword,
      dateOfBirth:     dateOfBirth,
      address:         address,
      spouseName:      spouseName.isEmpty ? nil : spouseName,
      spouseEmail:     spouseEmail.isEmpty ? nil : spouseEmail,
      spouseDob:       spouseDob.isEmpty ? nil : spouseDob,
      joinAsMember:    joinAsMember,
      captchaToken:    captchaToken
    ) { result in
      DispatchQueue.main.async {
        isSubmitting = false
        switch result {
        case .success((let token, _)):
          authToken = token
          presentationMode.wrappedValue.dismiss()
        case .failure(let err):
          alertTitle   = "Registration Failed"
          alertMessage = err.localizedDescription
          showAlert    = true
        }
      }
    }
  }
}
