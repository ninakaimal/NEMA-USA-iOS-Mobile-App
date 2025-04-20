//
//  LoginView.swift
//  NEMA USA
//
//  Created by Nina on 4/12/25.
//
import SwiftUI

struct LoginView: View {
    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage = ""
    @State private var isLoggedIn = false
    @State private var isLoading = false

    // Animation states
    @State private var logoScale: CGFloat = 1.4
    @State private var logoTopPadding: CGFloat = 200
    @State private var logoOpacity: Double = 0

    var body: some View {
        if isLoggedIn {
            WebView(url: URL(string: "https://mynema.ninascanvas.com")!)
        } else {
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
                                logoScale = 1.0
                                logoTopPadding = 40
                                logoOpacity = 1.0
                            }
                        }
                    
                    // NEMA Malayalam text
                    Text("NEW ENGLAND MALAYALEE ASSOCIATION")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.orange)
                        .multilineTextAlignment(.center)
                        .padding(.top, -10)
        
                    Text("ന്യൂ ഇംഗ്ലണ്ട് മലയാളി അസോസിയേഷൻ‍")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.orange)
                        .multilineTextAlignment(.center)
                        .padding(.top, -10)
                        .padding(.bottom, 40)


                    // Email Field
                    TextField("", text: $email)
                        .placeholder(when: email.isEmpty) {
                            Text("Email")
                                .foregroundColor(.orange.opacity(0.5))
                                .padding(.leading, 6)
                        }
                        .foregroundColor(.orange)
                        .tint(.orange)
                        .font(.system(size: 15))
                        .padding(12)
                        .background(Color.white)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(.orange, lineWidth: 0.5)
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
                                .foregroundColor(.orange.opacity(0.5))
                                .padding(.leading, 6)
                        }
                        .foregroundColor(.orange)
                        .tint(.orange)
                        .font(.system(size: 15))
                        .padding(12)
                        .background(Color.white)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(.orange, lineWidth: 1)
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
                        .background(.orange)
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
            //.background(Color.white)
            .background(Color(.systemBackground))
            .ignoresSafeArea(.keyboard)
        }
    }

    func login() {
        guard !email.isEmpty && !password.isEmpty else {
            errorMessage = "Please enter both email and password"
            return
        }

        isLoading = true
        errorMessage = ""

        guard let url = URL(string: "https://nema-api.kanakaagro.in/api/login") else {
            errorMessage = "Invalid API URL"
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload = ["email": email, "password": password]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async { isLoading = false }

            guard let data = data, error == nil else {
                DispatchQueue.main.async {
                    errorMessage = "Network error: \(error?.localizedDescription ?? "Unknown")"
                }
                return
            }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let token = json["token"] as? String {
                UserDefaults.standard.set(token, forKey: "nema_token")
                DispatchQueue.main.async {
                    isLoggedIn = true
                }
            } else {
                DispatchQueue.main.async {
                    errorMessage = "Invalid credentials"
                }
            }
        }.resume()
    }
}
