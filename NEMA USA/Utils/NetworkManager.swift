// NetworkManager.swift
// NEMA USA
// Created by Sajith on 4/20/25.
// Updated for token-refresh on 4/22/25.
// Arjun fixed duplicate updateProfile and added email/comments to the PUT body.

import Foundation

/// All the errors our networking layer can produce
enum NetworkError: Error {
    case serverError(String)      // underlying URLSession error or HTTP error
    case invalidResponse          // non-200 HTTP status or no data
    case decodingError(Error)     // JSON parsing failed
}

/// The JSON we expect from POST /api/login and /api/register
private struct LoginResponse: Decodable {
    let token: String
    let refreshToken: String
    let user: UserProfile
}

/// The JSON we expect from POST /api/refresh-token
private struct RefreshResponse: Decodable {
    let token: String
    let refreshToken: String
}

final class NetworkManager {
    static let shared = NetworkManager()
    private init() {}

    /// **Point at the `/api` root** so all your calls land in the right place.
    private let baseURL = URL(string: "https://nema-api.kanakaagro.in/api")!

    // MARK: – Helpers

    /// Update the current user's profile (must supply email+comments to satisfy the DB UPDATE)
    func updateProfile(
        name: String,
        phone: String,
        dateOfBirth: String,
        address: String,
        completion: @escaping (Result<UserProfile, NetworkError>) -> Void
    ) {
        guard let token = DatabaseManager.shared.authToken else {
            return completion(.failure(.invalidResponse))
        }
        let endpoint = baseURL.appendingPathComponent("profile")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "PUT"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        // include current email/comments so the backend's UPDATE doesn't reject null
        let current = DatabaseManager.shared.currentUser
        let body: [String: Any] = [
            "name":        name,
            "phone":       phone,
            "dateOfBirth": dateOfBirth,
            "address":     address,
            "email":       current?.email    ?? "",
            "comments":    current?.comments ?? ""
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        performRequest(request) { result in
            switch result {
            case .success(let data):
                do {
                    let updated = try JSONDecoder().decode(UserProfile.self, from: data)
                    completion(.success(updated))
                } catch {
                    completion(.failure(.decodingError(error)))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    /// Perform a URLRequest, retrying once after a token-refresh if we get a 401.
    private func performRequest(
        _ request: URLRequest,
        retrying: Bool = true,
        completion: @escaping (Result<Data, NetworkError>) -> Void
    ) {
        URLSession.shared.dataTask(with: request) { data, resp, err in
            if let err = err {
                DispatchQueue.main.async {
                    completion(.failure(.serverError(
                        "\(err.localizedDescription). Please check your connection and try again."
                    )))
                }
                return
            }
            guard let http = resp as? HTTPURLResponse else {
                DispatchQueue.main.async {
                    completion(.failure(.serverError(
                        "Unexpected response format. Please try again."
                    )))
                }
                return
            }
            if http.statusCode == 401, retrying {
                // try to refresh and then retry
                self.refreshToken { refreshResult in
                    switch refreshResult {
                    case .success(let newToken):
                        var newReq = request
                        newReq.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
                        self.performRequest(newReq, retrying: false, completion: completion)
                    case .failure:
                        DispatchQueue.main.async {
                            DatabaseManager.shared.clearSession()
                            completion(.failure(.invalidResponse))
                        }
                    }
                }
                return
            }
            guard (200..<300).contains(http.statusCode), let data = data else {
                DispatchQueue.main.async {
                    completion(.failure(.serverError(
                        "Server returned status \(http.statusCode). Please try again shortly."
                    )))
                }
                return
            }
            DispatchQueue.main.async { completion(.success(data)) }
        }
        .resume()
    }

    /// Call our `/refresh-token` endpoint, rotate tokens on success.
    private func refreshToken(completion: @escaping (Result<String, NetworkError>) -> Void) {
        guard let refresh = DatabaseManager.shared.refreshToken else {
            return completion(.failure(.invalidResponse))
        }
        let endpoint = baseURL.appendingPathComponent("refresh-token")
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONEncoder().encode(["refreshToken": refresh])

        URLSession.shared.dataTask(with: req) { data, resp, err in
            if let err = err {
                DispatchQueue.main.async { completion(.failure(.serverError(
                    "\(err.localizedDescription). Please check your connection and try again."
                ))) }
                return
            }
            guard let http = resp as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  let data = data
            else {
                DispatchQueue.main.async { completion(.failure(.invalidResponse)) }
                return
            }
            do {
                let decoded = try JSONDecoder().decode(RefreshResponse.self, from: data)
                DatabaseManager.shared.saveToken(decoded.token)
                DatabaseManager.shared.saveRefreshToken(decoded.refreshToken)
                DispatchQueue.main.async { completion(.success(decoded.token)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(.decodingError(error))) }
            }
        }
        .resume()
    }

    // MARK: – Public API

    func login(
        email: String,
        password: String,
        completion: @escaping (Result<(token: String, user: UserProfile), NetworkError>) -> Void
    ) {
        let endpoint = baseURL.appendingPathComponent("login")
        var request = URLRequest(url: endpoint)
        request.httpMethod   = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["email": email, "password": password]
        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            return DispatchQueue.main.async {
                completion(.failure(.decodingError(error)))
            }
        }

        URLSession.shared.dataTask(with: request) { data, resp, err in
            if let err = err {
                return DispatchQueue.main.async {
                    completion(.failure(.serverError(
                        "\(err.localizedDescription). Please check your network and try again."
                    )))
                }
            }
            guard let http = resp as? HTTPURLResponse else {
                return DispatchQueue.main.async {
                    completion(.failure(.serverError(
                        "Invalid server response. Please try again."
                    )))
                }
            }
            if http.statusCode == 401 {
                return DispatchQueue.main.async {
                    completion(.failure(.serverError(
                        "Invalid email or password. Please try again."
                    )))
                }
            }
            guard (200..<300).contains(http.statusCode), let data = data else {
                return DispatchQueue.main.async {
                    completion(.failure(.serverError(
                        "Login failed with status \(http.statusCode). Please try again."
                    )))
                }
            }
            do {
                let decoded = try JSONDecoder().decode(LoginResponse.self, from: data)
                DatabaseManager.shared.saveToken(decoded.token)
                DatabaseManager.shared.saveRefreshToken(decoded.refreshToken)
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

    /// Register a new user account
    func register(
        name: String,
        phone: String,
        email: String,
        confirmEmail: String,
        password: String,
        confirmPassword: String,
        dateOfBirth: String,
        address: String,
        spouseName: String?,
        spouseEmail: String?,
        spouseDob: String?,
        joinAsMember: Bool,
        captchaToken: String,
        completion: @escaping (Result<(token: String, user: UserProfile), NetworkError>) -> Void
    ) {
        let endpoint = baseURL.appendingPathComponent("register")
        var request = URLRequest(url: endpoint)
        request.httpMethod   = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any?] = [
            "name":           name,
            "phone":          phone,
            "email":          email,
            "confirmEmail":   confirmEmail,
            "password":       password,
            "confirmPassword":confirmPassword,
            "dateOfBirth":    dateOfBirth,
            "address":        address,
            "spouseName":     spouseName,
            "spouseEmail":    spouseEmail,
            "spouseDob":      spouseDob,
            "joinAsMember":   joinAsMember,
            "captchaToken":   captchaToken
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { data, resp, err in
            if let err = err {
                return DispatchQueue.main.async {
                    completion(.failure(.serverError(
                        "\(err.localizedDescription). Please check your network and try again."
                    )))
                }
            }
            guard let http = resp as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  let data = data
            else {
                return DispatchQueue.main.async {
                    completion(.failure(.invalidResponse))
                }
            }
            do {
                let decoded = try JSONDecoder().decode(LoginResponse.self, from: data)
                DatabaseManager.shared.saveToken(decoded.token)
                DatabaseManager.shared.saveRefreshToken(decoded.refreshToken)
                DatabaseManager.shared.saveUser(decoded.user)
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

    func fetchProfile(
        completion: @escaping (Result<UserProfile, NetworkError>) -> Void
    ) {
        guard let token = DatabaseManager.shared.authToken else {
            return completion(.failure(.invalidResponse))
        }
        let endpoint = baseURL.appendingPathComponent("profile")
        var req = URLRequest(url: endpoint)
        req.httpMethod = "GET"
        req.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        performRequest(req) { result in
            switch result {
            case .success(let data):
                do {
                    let profile = try JSONDecoder().decode(UserProfile.self, from: data)
                    completion(.success(profile))
                } catch {
                    completion(.failure(.decodingError(error)))
                }
            case .failure(let err):
                completion(.failure(err))
            }
        }
    }

    func fetchFamily(
        completion: @escaping (Result<[FamilyMember], NetworkError>) -> Void
    ) {
        guard let token = DatabaseManager.shared.authToken else {
            return completion(.failure(.invalidResponse))
        }
        let endpoint = baseURL.appendingPathComponent("family")
        var req = URLRequest(url: endpoint)
        req.httpMethod = "GET"
        req.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        performRequest(req) { result in
            switch result {
            case .success(let data):
                do {
                    let members = try JSONDecoder().decode([FamilyMember].self, from: data)
                    completion(.success(members))
                } catch {
                    completion(.failure(.decodingError(error)))
                }
            case .failure(let err):
                completion(.failure(err))
            }
        }
    }
}
