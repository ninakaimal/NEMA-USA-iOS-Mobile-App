//
//  NetworkManager.swift
//  NEMA USA
//  Created by Sajith on 4/20/25.
//  Centralized HTTP layer for all your network calls.
//

import Foundation

/// All the errors our networking layer can produce
enum NetworkError: Error {
    case serverError(String)      // underlying URLSession error
    case invalidResponse          // non‑200 HTTP status or no data
    case decodingError(Error)     // JSON parsing failed
}

/// Replace or remove this if you already have a `User` in Models/
struct User: Decodable {
    let id: String
    let name: String
    // …add any other fields your API returns…
}

final class NetworkManager {
    /// Singleton instance
    static let shared = NetworkManager()
    private init() {}

    /// Your real base URL → adjust to match your backend
    private let baseURL = URL(string: "https://nema-api.kanakaagro.in")!

    /// Logs in with email + password, calls completion on the main thread.
    func login(
        email: String,
        password: String,
        completion: @escaping (Result<(token: String, user: User), NetworkError>) -> Void
    ) {
        let endpoint = baseURL.appendingPathComponent("/auth/login")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        // Encode JSON body { "email": "...", "password": "..." }
        let body = ["email": email, "password": password]
        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            // Should never really happen with a simple [String:String]
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

            // 2️⃣ HTTP status code & data
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

            // 3️⃣ Decode JSON { "token": "...", "user": { ... } }
            do {
                struct LoginResponse: Decodable {
                    let token: String
                    let user: User
                }
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
}
