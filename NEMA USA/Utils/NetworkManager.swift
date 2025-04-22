//
//  NetworkManager.swift
//  NEMA USA
//  Created by Sajith on 4/20/25.
//

import Foundation

/// All the errors our networking layer can produce
enum NetworkError: Error {
    case serverError(String)      // underlying URLSession error
    case invalidResponse          // non‑200 HTTP status or no data
    case decodingError(Error)     // JSON parsing failed
}

/// The JSON we expect from POST /api/login
private struct LoginResponse: Decodable {
    let token: String
    let user: UserProfile
}

final class NetworkManager {
    static let shared = NetworkManager()
    private init() {}

    /// **Point at the `/api` root** so all your calls land in the right place.
    private let baseURL = URL(string: "https://nema-api.kanakaagro.in/api")!

    /// Logs in with email + password, returns token & full UserProfile
    func login(
        email: String,
        password: String,
        completion: @escaping (Result<(token: String, user: UserProfile), NetworkError>) -> Void
    ) {
        // ✅ now appends “login” → https://…/api/login
        let endpoint = baseURL.appendingPathComponent("login")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["email": email, "password": password]
        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            DispatchQueue.main.async {
                completion(.failure(.decodingError(error)))
            }
            return
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            // 1️⃣ Network error?
            if let err = error {
                DispatchQueue.main.async {
                    completion(.failure(.serverError(err.localizedDescription)))
                }
                return
            }

            // 2️⃣ Validate HTTP status & data
            guard
                let http = response as? HTTPURLResponse,
                (200..<300).contains(http.statusCode),
                let data = data
            else {
                DispatchQueue.main.async {
                    completion(.failure(.invalidResponse))
                }
                return
            }

            // 3️⃣ Decode JSON token + user
            do {
                let decoded = try JSONDecoder().decode(LoginResponse.self, from: data)
                DispatchQueue.main.async {
                    completion(.success((token: decoded.token, user: decoded.user)))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(.decodingError(error)))
                }
            }
        }
        .resume()
    }

    /// Fetch the logged‑in user’s profile
    func fetchProfile(
        token: String,
        completion: @escaping (Result<UserProfile, NetworkError>) -> Void
    ) {
        let endpoint = baseURL.appendingPathComponent("profile")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let err = error {
                DispatchQueue.main.async {
                    completion(.failure(.serverError(err.localizedDescription)))
                }
                return
            }
            guard
                let http = response as? HTTPURLResponse,
                (200..<300).contains(http.statusCode),
                let data = data
            else {
                DispatchQueue.main.async {
                    completion(.failure(.invalidResponse))
                }
                return
            }
            do {
                let profile = try JSONDecoder().decode(UserProfile.self, from: data)
                DispatchQueue.main.async {
                    completion(.success(profile))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(.decodingError(error)))
                }
            }
        }
        .resume()
    }

    /// Fetches the logged‑in user’s family members
    func fetchFamily(
        token: String,
        completion: @escaping (Result<[FamilyMember], NetworkError>) -> Void
    ) {
        let endpoint = baseURL.appendingPathComponent("family")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let err = error {
                DispatchQueue.main.async {
                    completion(.failure(.serverError(err.localizedDescription)))
                }
                return
            }
            guard
                let http = response as? HTTPURLResponse,
                (200..<300).contains(http.statusCode),
                let data = data
            else {
                DispatchQueue.main.async {
                    completion(.failure(.invalidResponse))
                }
                return
            }
            do {
                let members = try JSONDecoder().decode([FamilyMember].self, from: data)
                DispatchQueue.main.async {
                    completion(.success(members))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(.decodingError(error)))
                }
            }
        }
        .resume()
    }
}

