
//
//  AccountView.swift
//  NEMA USA
//  Created by Arjun on 4/15/25.
//

import SwiftUI

struct AccountView: View {
    // 1) Watch the same key where LoginView writes the token
    @AppStorage("authToken") private var authToken: String?

    @State private var profile: UserProfile?
    @State private var isLoading = false

    var body: some View {
        Group {
            // 2) If no token, show login form
            if authToken == nil {
                LoginView()
            }
            // 3) While we’re fetching, show spinner
            else if isLoading {
                ProgressView("Loading profile…")
            }
            // 4) Once loaded, display profile
            else if let p = profile {
                VStack(spacing: 16) {
                    Image(systemName: "person.crop.circle.fill")
                        .resizable()
                        .frame(width: 100, height: 100)
                        .foregroundColor(.orange)

                    Text(p.name)
                        .font(.title2)
                        .bold()

                    HStack {
                        Text("Phone:")
                        Spacer()
                        Text(p.phone)
                    }

                    HStack {
                        Text("Email:")
                        Spacer()
                        Text(p.email)
                    }

                    HStack {
                        Text("Date of Birth:")
                        Spacer()
                        Text(p.dob ?? "Not set")
                    }

                    HStack {
                        Text("Address:")
                        Spacer()
                        Text(p.address)
                    }

                    if let comments = p.comments {
                        Text("Note: \(comments)")
                            .italic()
                            .font(.footnote)
                    }

                    Spacer()
                }
                .padding()
            }
            // 5) No profile found in both network & cache
            else {
                Text("Profile not found.")
            }
        }
        // 6) Trigger loadProfile on first appear if we have a token
        .onAppear {
            if authToken != nil {
                loadProfile()
            }
        }
        // 7) Also trigger loadProfile whenever the token flips non‑nil
        .onChange(of: authToken) { new in
            if new != nil {
                loadProfile()
            }
        }
        .navigationBarTitle("Account", displayMode: .inline)
    }

    // MARK: – Profile Loading

    private func loadProfile() {
        guard let token = authToken,
              let url   = URL(string: "https://nema-api.kanakaagro.in/api/profile")
        else {
            // no token → stop loading
            isLoading = false
            return
        }

        isLoading = true

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: req) { data, _, error in
            DispatchQueue.main.async { isLoading = false }

            if let data = data {
                // debug raw payload
                if let raw = String(data: data, encoding: .utf8) {
                    print("⤷ [Profile] raw response: \(raw)")
                }
                // try decoding fresh
                if let fetched = try? JSONDecoder().decode(UserProfile.self, from: data) {
                    DispatchQueue.main.async {
                        profile = fetched
                        // cache locally for offline
                        DatabaseManager.shared.saveUser(fetched)
                    }
                    return
                }
            }

            // fallback to cached UserProfile if decode or network fails
            if let cached = DatabaseManager.shared.currentUser {
                DispatchQueue.main.async {
                    profile = cached
                }
            }
        }
        .resume()
    }
}
