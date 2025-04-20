//
//  ProfileView.swift
//  NEMA USA
//
//  Created by Arjun on 4/15/25.
//
import SwiftUI

struct ProfileView: View {
    @State private var profile: UserProfile?
    @State private var isLoading = true
    @State private var isLoggedIn = UserDefaults.standard.string(forKey: "nema_token") != nil

    let orange = Color(hex: "F97316")

    var body: some View {
        Group {
            if !isLoggedIn {
                LoginView() // ✅ fallback if not logged in
            } else if isLoading {
                ProgressView("Loading profile...")
            } else if let profile = profile {
                VStack(spacing: 16) {
                    Image(systemName: "person.crop.circle.fill")
                        .resizable()
                        .frame(width: 100, height: 100)
                        .foregroundColor(orange)

                    Text(profile.name)
                        .font(.title2)
                        .bold()

                    HStack {
                        Text("Email:")
                        Spacer()
                        Text(profile.email)
                    }

                    HStack {
                        Text("Phone:")
                        Spacer()
                        Text(profile.phone)
                    }

                    HStack {
                        Text("Address:")
                        Spacer()
                        Text(profile.address)
                    }

                    HStack {
                        Text("Date of Birth:")
                        Spacer()
                        Text(profile.dob ?? "Not set")
                    }

                    if let comments = profile.comments {
                        Text("Note: \(comments)")
                            .italic()
                            .font(.footnote)
                    }

                    Spacer()
                }
                .padding()
            } else {
                Text("Profile not found.")
            }
        }
        .onAppear(perform: fetchProfile)
        .navigationBarTitle("My Profile", displayMode: .inline)
    }

    func fetchProfile() {
        guard let token = UserDefaults.standard.string(forKey: "nema_token"),
              let url = URL(string: "https://nema-api.kanakaagro.in/api/profile") else {
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { data, _, error in
            DispatchQueue.main.async {
                isLoading = false
            }

            guard let data = data, error == nil else { return }

            if let decoded = try? JSONDecoder().decode(UserProfile.self, from: data) {
                DispatchQueue.main.async {
                    profile = decoded
                }
            }
        }.resume()
    }
}
