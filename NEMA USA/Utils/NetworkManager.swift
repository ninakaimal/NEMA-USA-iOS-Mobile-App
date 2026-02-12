//
//  NetworkManager.swift
//  NEMA USA
//  Created by Sajith on 4/20/25.
//  Updated for token-refresh on 4/22/25.
//  Added updateFamily on 5/10/25.
//

import Foundation
import SwiftSoup

struct MobileMembershipPackage: Decodable {
  let id: Int
  let name: String
  let amount: Double
  let years_of_validity: Int
}

struct Membership: Decodable {
  let id: Int
  let user_id: Int
  let membership_pkg_id: Int
  let amount: Double
  let exp_date: String
  let package: MobileMembershipPackage?
}

/// All the errors our networking layer can produce
enum NetworkError: Error {
    case serverError(String)      // underlying URLSession error or HTTP error
    case invalidResponse          // non-200 HTTP status, no data, or bad HTML
    case decodingError(Error)     // JSON parsing failed
}

/// For your JSON-based register/login paths
private struct LoginResponse: Decodable {
    let token: String
    let refreshToken: String
    
}

private struct RefreshResponse: Decodable {
    let token: String
    let refreshToken: String
}

/// A delegate to unconditionally trust the nemausa.org cert
//public class InsecureTrustDelegate: NSObject, URLSessionDelegate {
//    public func urlSession(_ session: URLSession,
//                    didReceive challenge: URLAuthenticationChallenge,
//                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void)
//    {
//        let host = challenge.protectionSpace.host
//        if host == "nemausa.org",
//           let trust = challenge.protectionSpace.serverTrust
//        {
//            completionHandler(.useCredential, URLCredential(trust: trust))
//        } else {
//            completionHandler(.performDefaultHandling, nil)
//        }
//    }
//}

private enum DateFormatters {
    
    // Formatter 1: Handles dates with timezone offset AND fractional seconds
    static let withFractionalSecondsOffset: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime, .withFractionalSeconds, .withColonSeparatorInTimeZone]
        return formatter
    }()

    // Formatter 2: Handles dates with timezone offset but NO fractional seconds
    static let withoutFractionalSecondsOffset: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime, .withColonSeparatorInTimeZone]
        return formatter
    }()
    
    // Formatter 3: Handles Zulu time (UTC) with fractional seconds
    static let zuluWithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime, .withFractionalSeconds, .withTimeZone]
        return formatter
    }()

    // Formatter 4: Handles Zulu time (UTC) WITHOUT fractional seconds
    static let zuluWithoutFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime, .withTimeZone]
        return formatter
    }()
    
    // Formatter 5: Date only
    static let dateOnly: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withDashSeparatorInDate]
        return formatter
    }()
}

final class NetworkManager: NSObject {
    static let shared = NetworkManager()
    
    // MOVED: Connection management properties (previously global)
    private var activeConnections: Set<URLSessionDataTask> = []
    private let connectionQueue = DispatchQueue(label: "network.connections", qos: .utility)

    private lazy var programSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10.0
        config.timeoutIntervalForResource = 15.0
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil // Prevent connection reuse issues
        return URLSession(configuration: config)
    }()

    private func cleanupConnection(_ task: URLSessionDataTask) {
        connectionQueue.async {
            self.activeConnections.remove(task)
        }
    }

    private var activeTicketRequests: [Int: Task<TicketPurchaseDetailResponse, Error>] = [:]
    private var activeProgramRequests: [Int: Task<Participant, Error>] = [:]
    private let requestQueue = DispatchQueue(label: "NetworkManager.requestQueue", attributes: .concurrent)

    private override init() {}
    
    /// For your JSON‐based register/login paths
    func loginJSON(
        email: String,
        password: String,
        completion: @escaping (Result<(token: String, user: UserProfile), NetworkError>) -> Void
    ) {
        let url = baseURL.appendingPathComponent("v1/login")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONEncoder().encode(["email": email, "password": password])
        
        session.dataTask(with: req) { data, resp, err in
            guard err == nil,
                  let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let d = data
            else {
                return DispatchQueue.main.async {
                    completion(.failure(.invalidResponse))
                }
            }
            
            do {
                let loginResp = try self.iso8601JSONDecoder.decode(LoginResponse.self, from: d)
                DatabaseManager.shared.saveJwtApiToken(loginResp.token)
                DatabaseManager.shared.saveRefreshToken(loginResp.refreshToken)
                
                // now fetch the real UserProfile (including expiry date)
                self.fetchProfileJSON { result in
                    DispatchQueue.main.async {
                        switch result {
                        case .success(let profile):
                            DatabaseManager.shared.saveUser(profile)
                            // Ensure these lines are included: Remove
                            UserDefaults.standard.set(profile.name, forKey: "memberName")
                            UserDefaults.standard.set(profile.email, forKey: "emailAddress")
                            UserDefaults.standard.set(profile.phone, forKey: "phoneNumber")
                            
                            UserDefaults.standard.set(profile.id, forKey: "userId")
                            completion(.success((token: loginResp.token, user: profile)))
                        case .failure(let err):
                            completion(.failure(err))
                        }
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(.decodingError(error)))
                }
            }
        }
        .resume()
    }
    
    /// Keep Laravel’s XSRF-TOKEN + session cookie automatically
    private lazy var session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.httpCookieAcceptPolicy = .always
        cfg.httpCookieStorage     = HTTPCookieStorage.shared
        // disabling unsigned SSL piece in production
        //return URLSession(configuration: cfg,
        //                  delegate: InsecureTrustDelegate(),
        //                  delegateQueue: nil)
        return URLSession(configuration: cfg) //replaced above sandbox code with this
    }()
    
    /// A special session for login so we can catch the 302 redirect
    private lazy var loginSession: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.httpCookieAcceptPolicy = .always
        cfg.httpCookieStorage     = HTTPCookieStorage.shared
        return URLSession(configuration: cfg,
                          delegate: self,
                          delegateQueue: nil)
    }()
    
    private lazy var iso8601JSONDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder throws -> Date in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            
            // Attempt to decode with the pre-built, static formatters
            if let date = DateFormatters.withoutFractionalSecondsOffset.date(from: dateString) { return date }
            if let date = DateFormatters.withFractionalSecondsOffset.date(from: dateString) { return date }
            if let date = DateFormatters.zuluWithoutFractionalSeconds.date(from: dateString) { return date }
            if let date = DateFormatters.zuluWithFractionalSeconds.date(from: dateString) { return date }
            if let date = DateFormatters.dateOnly.date(from: dateString) { return date }
            
            let codingPathString = container.codingPath.map { $0.stringValue }.joined(separator: ".")
            print("🚨 Custom Date Decoding Failed for key path '\(codingPathString)': String '\(dateString)' could not be parsed.")
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Date string does not match any expected ISO8601 format.")
        }
        return decoder
    }()
    
    /// Your front-end root
    private let baseURL = URL(string: "https://nemausa.org")!
    
    
    // MARK: – Helpers
    
    // Send reset password link
    func sendPasswordResetLink(email: String, completion: @escaping (Result<String, NetworkError>) -> Void) {
        fetchCSRFToken { result in
            switch result {
            case .failure(let error):
                print("⚠️ CSRF token fetch error:", error.localizedDescription)
                DispatchQueue.main.async {
                    completion(.failure(.serverError("CSRF token error: \(error.localizedDescription)")))
                }
            case .success(let csrfToken):
                let endpoint = URL(string: "https://nemausa.org/user/reset/password")!
                var req = URLRequest(url: endpoint)
                req.httpMethod = "POST"
                req.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
                
                let params = [
                    "_token": csrfToken,
                    "email": email
                ]
                
                req.httpBody = params.map { "\($0)=\($1.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
                    .joined(separator: "&")
                    .data(using: .utf8)
                
                print("🚀 [sendPasswordResetLink] Sending request to: \(endpoint.absoluteString) with email: \(email)")
                
                self.session.dataTask(with: req) { data, response, error in
                    if let error = error {
                        print("❌ [sendPasswordResetLink] Error:", error.localizedDescription)
                        DispatchQueue.main.async {
                            completion(.failure(.serverError(error.localizedDescription)))
                        }
                        return
                    }
                    
                    guard let httpResponse = response as? HTTPURLResponse else {
                        print("❌ [sendPasswordResetLink] Non-HTTP Response")
                        DispatchQueue.main.async {
                            completion(.failure(.invalidResponse))
                        }
                        return
                    }
                    
                    print("🔄 [sendPasswordResetLink] HTTP Response Status Code: \(httpResponse.statusCode)")
                    
                    guard (200..<400).contains(httpResponse.statusCode) else {
                        let bodyText = String(data: data ?? Data(), encoding: .utf8) ?? "No response body"
                        print("❌ [sendPasswordResetLink] HTTP Status Error \(httpResponse.statusCode): \(bodyText)")
                        DispatchQueue.main.async {
                            completion(.failure(.serverError("HTTP \(httpResponse.statusCode)")))
                        }
                        return
                    }
                    
                    DispatchQueue.main.async {
                        print("✅ [sendPasswordResetLink] Reset link successfully sent.")
                        completion(.success("Reset link sent to your email."))
                    }
                }.resume()
            }
        }
    }
    
    
    // Reset password function
    func resetPassword(token: String, newPassword: String, completion: @escaping (Result<String, NetworkError>) -> Void) {
        fetchCSRFToken { result in
            switch result {
            case .failure(let error):
                print("⚠️ CSRF token fetch error:", error.localizedDescription)
                DispatchQueue.main.async {
                    completion(.failure(.serverError("CSRF token error: \(error.localizedDescription)")))
                }
            case .success(let csrfToken):
                let endpoint = URL(string: "https://nemausa.org/user/reset_password")!
                var req = URLRequest(url: endpoint)
                req.httpMethod = "POST"
                req.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
                
                let params = [
                    "_token": csrfToken,
                    "token": token,
                    "password": newPassword,
                    "cnf_password": newPassword
                ]
                
                req.httpBody = params.map { "\($0)=\($1.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
                    .joined(separator: "&")
                    .data(using: .utf8)
                
                print("🚀 [resetPassword] Sending request to: \(endpoint.absoluteString) with reset token: \(token)")
                
                self.session.dataTask(with: req) { data, response, error in
                    if let error = error {
                        print("❌ [resetPassword] Transport Error:", error.localizedDescription)
                        DispatchQueue.main.async {
                            completion(.failure(.serverError(error.localizedDescription)))
                        }
                        return
                    }
                    
                    guard let httpResponse = response as? HTTPURLResponse else {
                        print("❌ [resetPassword] Invalid response: Not HTTP.")
                        DispatchQueue.main.async {
                            completion(.failure(.invalidResponse))
                        }
                        return
                    }
                    
                    print("🔄 [resetPassword] HTTP Response Status Code:", httpResponse.statusCode)
                    
                    guard (200..<400).contains(httpResponse.statusCode) else {
                        let bodyText = data.flatMap { String(data: $0, encoding: .utf8) } ?? "No response body"
                        print("❌ [resetPassword] HTTP Status Error \(httpResponse.statusCode): \(bodyText)")
                        DispatchQueue.main.async {
                            completion(.failure(.serverError("HTTP Status: \(httpResponse.statusCode), body: \(bodyText)")))
                        }
                        return
                    }
                    
                    print("✅ [resetPassword] Password reset successful.")
                    
                    DispatchQueue.main.async {
                        completion(.success("Your password has been reset successfully."))
                    }
                }.resume()
            }
        }
    }
    
    /// 1) Fetch the hidden Laravel CSRF token from the form
    func fetchCSRFToken(completion: @escaping (Result<String, Error>) -> Void) {
        var comps = URLComponents(
            url: baseURL.appendingPathComponent("sign_in_form"),
            resolvingAgainstBaseURL: false
        )!
        comps.queryItems = [
            .init(name: "previous", value: "\(baseURL)/profile")
        ]
        guard let url = comps.url else {
            return completion(.failure(
                NSError(domain: "CSRF", code: 0, userInfo: [
                    NSLocalizedDescriptionKey: "Bad URL building CSRF request"
                ])
            ))
        }
        session.dataTask(with: url) { data, _, error in
            if let e = error { return completion(.failure(e)) }
            guard let bytes = data,
                  let html  = String(data: bytes, encoding: .utf8)
            else { return completion(.failure(NSError(domain: "CSRF", code: 0))) }
            do {
                let doc   = try SwiftSoup.parse(html)
                let token = try doc.select("input[name=_token]").first()?.attr("value") ?? ""
                DispatchQueue.main.async {
                   // print("✅ fetched CSRF token:", token)
                    completion(.success(token))
                }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
        .resume()
    }
    
    // MARK: – Option B: form-POST + HTML-scrape
    
    /// 1) POST `/user_login`
    /// 2) inspect the 302 → then scrape `/profile`
    func login(
        email: String,
        password: String,
        completion: @escaping (Result<(token: String, user: UserProfile), NetworkError>) -> Void
    ) {
        fetchCSRFToken { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .failure(let err):
                DispatchQueue.main.async {
                    completion(.failure(.serverError(
                        "Login failed (couldn’t fetch CSRF token): \(err.localizedDescription)"
                    )))
                }
            case .success(let csrfToken):
                let url = self.baseURL.appendingPathComponent("user_login")
                var req = URLRequest(url: url)
                req.httpMethod = "POST"
                req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
                req.setValue("\(self.baseURL)/sign_in_form?previous=/profile",
                             forHTTPHeaderField: "Referer")
                
                func urlEncode(_ s: String) -> String {
                    s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s
                }
                let body = [
                    "_token=\(urlEncode(csrfToken))",
                    "previous=/profile",
                    "email=\(urlEncode(email))",
                    "password=\(urlEncode(password))"
                ].joined(separator: "&")
                req.httpBody = body.data(using: .utf8)
                
                self.loginSession.dataTask(with: req) { _, resp, err in
                    if let e = err {
                        return DispatchQueue.main.async {
                            completion(.failure(.serverError(
                                "\(e.localizedDescription). Please check your network."
                            )))
                        }
                    }
                    guard let http = resp as? HTTPURLResponse else {
                        return DispatchQueue.main.async {
                            completion(.failure(.invalidResponse))
                        }
                    }
                    
                    // Laravel always 302s form-POST
                    if (300..<400).contains(http.statusCode) {
                        let location = http.value(forHTTPHeaderField: "Location") ?? ""
                        // bounced back to login form → bad creds
                        if location.contains("sign_in_form") {
                            return DispatchQueue.main.async {
                                completion(.failure(.serverError(
                                    "Invalid email or password. Please try again."
                                )))
                            }
                        }
                        // else → success, scrape profile
                        self.fetchProfile { scrapeResult in
                            DispatchQueue.main.async {
                                switch scrapeResult {
                                case .failure(let err):
                                    completion(.failure(err))
                                case .success(let profile):
                                    let dummyToken = "LARAVEL_SESSION"
                                    // persist it under your new key
                                    DatabaseManager.shared.saveLaravelSessionToken(dummyToken)
                                    DatabaseManager.shared.saveUser(profile)
                                    completion(.success((token: dummyToken, user: profile)))
                                }
                            }
                        }
                        return
                    }
                    
                    // anything else → unexpected
                    DispatchQueue.main.async {
                        completion(.failure(.serverError(
                            "Login failed (status \(http.statusCode))."
                        )))
                    }
                }
                .resume()
            }
        }
    }
    
    // Scrape `/profile` HTML → UserProfile
    func fetchProfile(completion: @escaping (Result<UserProfile, NetworkError>) -> Void) {
        let url = baseURL.appendingPathComponent("profile")
        session.dataTask(with: url) { data, _, err in
            if let e = err {
                return DispatchQueue.main.async {
                    completion(.failure(.serverError(
                        "Profile request failed: \(e.localizedDescription)"
                    )))
                }
            }
            guard let bytes = data,
                  let html  = String(data: bytes, encoding: .utf8)
            else {
                return DispatchQueue.main.async {
                    completion(.failure(.invalidResponse))
                }
            }
            do {
                let doc     = try SwiftSoup.parse(html)
                let name    = try doc.select("input[name=name]").first()?.attr("value") ?? ""
                let email   = try doc.select("input[name=email]").first()?.attr("value") ?? ""
                let phone   = try doc.select("input[name=phone]").first()?.attr("value") ?? ""
                let dob     = try doc.select("input[name=dateOfBirth]").first()?.attr("value") ?? ""
                let address = try doc.select("textarea[name=address]").first()?.text() ?? ""
                
                // 1) try the (now-removed) input just in case
                let inputRaw = try doc.select("input[name=exp_date]")
                    .first()?.attr("value") ?? ""
                
                // 2) new fallback: the <span> immediately after the <label>
                let spanRaw = try doc
                    .select("label:containsOwn(Your Membership Will Expire On) + span.text-danger")
                    .first()?.text() ?? ""
                
                // 3) pick whichever is nonempty
                let expiryRaw = !inputRaw.isEmpty ? inputRaw : spanRaw
                
                
                let profile = UserProfile(
                    id:                   0,
                    name:                 name,
                    dateOfBirth:          dob,
                    address:              address,
                    email:                email,
                    phone:                phone,
                    comments:             nil,
                    membershipExpiryDate: expiryRaw.isEmpty ? nil : expiryRaw
                )
                DispatchQueue.main.async {
                    completion(.success(profile))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(.serverError(
                        "Profile parse error: \(error.localizedDescription)"
                    )))
                }
            }
        }
        .resume()
    }
    
    /// GET /v1/mobile/family-members
    func fetchFamily(completion: @escaping (Result<[FamilyMember], NetworkError>) -> Void) {
        guard let jwt = DatabaseManager.shared.jwtApiToken else {
            return completion(.failure(.invalidResponse))
        }
        
        let url = baseURL.appendingPathComponent("v1/mobile/family-members")
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        
        performRequest(req) { result in
            switch result {
            case .failure(let e):
                DispatchQueue.main.async {
                    completion(.failure(e))
                }
            case .success(let data):
                do {
                    let members = try self.iso8601JSONDecoder.decode([FamilyMember].self, from: data)
                    DatabaseManager.shared.saveFamily(members)
                    DispatchQueue.main.async {
                        completion(.success(members))
                    }
                } catch {
                    DispatchQueue.main.async {
                        completion(.failure(.decodingError(error)))
                    }
                }
            }
        }
    }
    
    // MARK: – JSON-based methods
    
    // 1) Public list of packages
    func fetchMembershipPackages(
        completion: @escaping (Result<[MobileMembershipPackage], NetworkError>) -> Void
    ) {
        let url = baseURL.appendingPathComponent("v1/mobile/membership/packages")
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        session.dataTask(with: req) { data, resp, err in
            if let e = err { return DispatchQueue.main.async { completion(.failure(.serverError(e.localizedDescription))) } }
            guard
                let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                let d = data
            else { return DispatchQueue.main.async { completion(.failure(.invalidResponse)) } }
            do {
                let packs = try self.iso8601JSONDecoder.decode([MobileMembershipPackage].self, from: d)
                DispatchQueue.main.async { completion(.success(packs)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(.decodingError(error))) }
            }
        }.resume()
    }
    
    // 2) Get the user’s current membership
    func fetchMembership(
        completion: @escaping (Result<Membership, NetworkError>) -> Void
    ) {
        guard let jwt = DatabaseManager.shared.jwtApiToken else {
            return completion(.failure(.invalidResponse))
        }
        let url = baseURL.appendingPathComponent("v1/mobile/membership")
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        session.dataTask(with: req) { data, resp, err in
            if let e = err { return DispatchQueue.main.async { completion(.failure(.serverError(e.localizedDescription))) } }
            guard
                let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                let d = data
            else { return DispatchQueue.main.async { completion(.failure(.invalidResponse)) } }
            do {
                let m = try self.iso8601JSONDecoder.decode(Membership.self, from: d)
                DispatchQueue.main.async { completion(.success(m)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(.decodingError(error))) }
            }
        }.resume()
    }
    
    // 3) Create membership
    func createMembership(
        packageId: Int,
        onlinePaymentId: Int?, // <<<< ADD this parameter
        completion: @escaping (Result<Membership, NetworkError>) -> Void
    ) {
        guard let jwt = DatabaseManager.shared.jwtApiToken else {
            return completion(.failure(.invalidResponse))
        }
        let url = baseURL.appendingPathComponent("v1/mobile/membership") // POST to this for creation
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = ["package_id": packageId]
        if let paymentId = onlinePaymentId {
            body["online_payment_id"] = paymentId // Pass this to the backend
        }

        do {
            req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        } catch {
            DispatchQueue.main.async {
                completion(.failure(.serverError("Failed to encode request body for create: \(error.localizedDescription)")))
            }
            return
        }

        performRequest(req) { result in
            switch result {
            case .failure(let e): completion(.failure(e))
            case .success(let data):
                do {
                    let m = try self.iso8601JSONDecoder.decode(Membership.self, from: data)
                    completion(.success(m))
                } catch {
                    completion(.failure(.decodingError(error)))
                }
            }
        }
    }
    
    // 4) Renew membership
    func renewMembership(
        packageId: Int,
        onlinePaymentId: Int?, // Ensure this parameter is present
        completion: @escaping (Result<Membership, NetworkError>) -> Void
    ) {
        guard let jwt = DatabaseManager.shared.jwtApiToken else {
            return completion(.failure(.invalidResponse))
        }
        let url = baseURL.appendingPathComponent("v1/mobile/membership/renew")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = ["package_id": packageId]
        if let paymentId = onlinePaymentId {
            body["online_payment_id"] = paymentId // Pass this to the backend
        }

        // Use JSONSerialization if your body is [String: Any]
        // Ensure 'body' can be encoded by your 'performRequest' or encode here
        do {
            req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        } catch {
            DispatchQueue.main.async {
                completion(.failure(.serverError("Failed to encode request body: \(error.localizedDescription)")))
            }
            return
        }

        performRequest(req) { result in
            switch result {
            case .failure(let e): completion(.failure(e))
            case .success(let data):
                do {
                    // and your Membership struct matches the backend response.
                    let m = try self.iso8601JSONDecoder.decode(Membership.self, from: data)
                    completion(.success(m))
                } catch {
                    completion(.failure(.decodingError(error)))
                }
            }
        }
    }
    
    
    /// GET /api/user → JSON User object including membershipExpiryDate & id
    func fetchProfileJSON(completion: @escaping (Result<UserProfile, NetworkError>) -> Void) {
        guard let jwt = DatabaseManager.shared.jwtApiToken else {
            return completion(.failure(.invalidResponse))
        }
        let url = baseURL.appendingPathComponent("v1/user")
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.addValue("application/json", forHTTPHeaderField: "Accept")
        req.addValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        
        session.dataTask(with: req) { data, resp, err in
            if let e = err {
                return DispatchQueue.main.async {
                    completion(.failure(.serverError(e.localizedDescription)))
                }
            }
            guard let http = resp as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  let d = data
            else {
                return DispatchQueue.main.async {
                    completion(.failure(.invalidResponse))
                }
            }
            do {
                let profile = try self.iso8601JSONDecoder.decode(UserProfile.self, from: d)
                // ✅ store the user-id for future calls
                UserDefaults.standard.set(profile.id, forKey: "userId")
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
    
    /// POST `/profile` form-URL-encoded
    func updateProfile(
        name: String,
        phone: String,
        address: String,
        dob: String,
        completion: @escaping (Result<UserProfile, NetworkError>) -> Void
    ) {
        guard let jwt = DatabaseManager.shared.jwtApiToken else {
            return completion(.failure(.invalidResponse))
        }
        let url = baseURL.appendingPathComponent("v1/user")
        var req = URLRequest(url: url)
        req.httpMethod = "PATCH"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.addValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        
        let params = [
            "name": name,
            "phone": phone,
            "address": address,
            "dob": dob
        ]
        req.httpBody = try? JSONEncoder().encode(params)
        
        performRequest(req) { result in
            switch result {
            case .failure(let e):
                DispatchQueue.main.async {
                    completion(.failure(e))
                }
            case .success(let data):
                do {
                    let profile = try self.iso8601JSONDecoder.decode(UserProfile.self, from: data)
                    // Save to local storage (this was done in fetchProfileJSON before)
                    DatabaseManager.shared.saveUser(profile)
                    UserDefaults.standard.set(profile.id, forKey: "userId")
                    DispatchQueue.main.async {
                        completion(.success(profile))
                    }
                } catch {
                    DispatchQueue.main.async {
                        completion(.failure(.decodingError(error)))
                    }
                }
            }
        }
    }
    
    func deleteAccount(completion: @escaping (Result<Void, NetworkError>) -> Void) {
        guard let jwt = DatabaseManager.shared.jwtApiToken else {
            return completion(.failure(.serverError("User not authenticated.")))
        }
        
        // This URL must match the route you defined in your backend
        let url = baseURL.appendingPathComponent("v1/user")
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE" // Use the DELETE HTTP method
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")

        print("[NetworkManager] Sending request to delete user account.")

        session.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("[NetworkManager] Delete account transport error: \(error.localizedDescription)")
                    completion(.failure(.serverError(error.localizedDescription)))
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse else {
                    print("[NetworkManager] Delete account invalid response.")
                    completion(.failure(.invalidResponse))
                    return
                }
                
                // A successful deletion can return 200 OK with a message, or 204 No Content.
                if (200..<300).contains(httpResponse.statusCode) {
                    print("[NetworkManager] Account successfully deleted on backend.")
                    completion(.success(()))
                } else {
                    let errorBody = data.flatMap { String(data: $0, encoding: .utf8) } ?? "No response body"
                    print("[NetworkManager] Delete account failed with status \(httpResponse.statusCode). Body: \(errorBody)")
                    completion(.failure(.serverError("Could not delete account. Server responded with status \(httpResponse.statusCode).")))
                }
            }
        }.resume()
    }
    
    /// POST /v1/mobile/family-members
    func addNewFamilyMember(
        name: String,
        relationship: String,
        email: String?,
        dob: String?,
        phone: String?,
        completion: @escaping (Result<Void, NetworkError>) -> Void
    ) {
        guard let jwt = DatabaseManager.shared.jwtApiToken else {
            return completion(.failure(.invalidResponse))
        }
        
        let url = baseURL.appendingPathComponent("v1/mobile/family-members")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var body: [String: Any] = [
            "name": name,
            "relationship": relationship
        ]
        if let email = email, !email.isEmpty { body["email"] = email }
        if let phone = phone, !phone.isEmpty { body["phone"] = phone }
        if let dob = dob, !dob.isEmpty { body["dob"] = dob }
        
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        performRequest(req) { result in
            switch result {
            case .failure(let e):
                DispatchQueue.main.async {
                    completion(.failure(e))
                }
            case .success:
                DispatchQueue.main.async {
                    completion(.success(()))
                }
            }
        }
    }

    /// Update family members individually
    func updateFamily(
        _ members: [FamilyMember],
        completion: @escaping (Result<Void, NetworkError>) -> Void
    ) {
        guard let jwt = DatabaseManager.shared.jwtApiToken else {
            return completion(.failure(.invalidResponse))
        }
        
        let group = DispatchGroup()
        var anyError: NetworkError?
        
        for member in members {
            group.enter()
            
            let url = baseURL.appendingPathComponent("v1/mobile/family-members/\(member.id)")
            var req = URLRequest(url: url)
            req.httpMethod = "PUT"
            req.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let body: [String: Any] = [
                "name": member.name,
                "relationship": member.relationship,
                "email": member.email ?? "",
                "phone": member.phone ?? "",
                "dob": member.dob ?? ""
            ]
            
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
            
            performRequest(req) { result in
                if case .failure(let error) = result {
                    anyError = error
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            if let err = anyError {
                completion(.failure(err))
            } else {
                completion(.success(()))
            }
        }
    }
    
    /// DELETE /v1/mobile/family-members/{id}
    func deleteFamilyMember(
        memberId: Int,
        completion: @escaping (Result<Void, NetworkError>) -> Void
    ) {
        guard let jwt = DatabaseManager.shared.jwtApiToken else {
            return completion(.failure(.invalidResponse))
        }
        
        let url = baseURL.appendingPathComponent("v1/mobile/family-members/\(memberId)")
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        req.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        
        performRequest(req) { result in
            switch result {
            case .failure(let e):
                DispatchQueue.main.async {
                    completion(.failure(e))
                }
            case .success:
                DispatchQueue.main.async {
                    completion(.success(()))
                }
            }
        }
    }
    
    private var eventsApiBaseURL: URL { // Helper to construct the correct base for these new v1 APIs
        // Assuming your Dingo API routes are prefixed with /api
        // If your baseURL is "https://nemausa.org", and Dingo routes are under "/api",
        // then this should correctly point to "https://nemausa.org/api/"
        // The Dingo router in your api.php seems to handle the /v1 prefix automatically based on versioning.
        return baseURL.appendingPathComponent("v1/mobile/") // Path to your new mobile API folder/routes
    }
    // Re-use or define date formatter for 'since' parameter
    private static let iso8601DateTimeFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds, .withColonSeparatorInTimeZone]
        return formatter
    }()

    // 1. Fetch Events
    func fetchEvents(since: Date?) async throws -> (events: [Event], deletedEventIds: [String]) {
        var urlComponents = URLComponents(url: eventsApiBaseURL.appendingPathComponent("events"), resolvingAgainstBaseURL: false)!
        var queryItems: [URLQueryItem] = []

        if let sinceDate = since {
            queryItems.append(URLQueryItem(name: "since", value: NetworkManager.iso8601DateTimeFormatter.string(from: sinceDate)))
        }
        // Add 'deleted_since' parameter handling here if your backend supports it for deleted IDs

        if !queryItems.isEmpty {
            urlComponents.queryItems = queryItems
        }

        guard let url = urlComponents.url else {
            print("❌ [NetworkManager] fetchEvents: Bad URL components.")
            throw NetworkError.serverError("Bad URL for fetching events.") // Or a more specific error
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("application/json", forHTTPHeaderField: "Accept")

        // Add JWT token if your event listing API endpoint requires authentication
        // if let token = DatabaseManager.shared.jwtApiToken {
        //     request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        // }

        print("🚀 [NetworkManager] Fetching events from: \(url.absoluteString)")

        let (data, response) = try await session.data(for: request) // Use your existing 'session'
        
 //       // --- ADD THIS LOGGING BLOCK TO SEE THE RAW JSON ---
 //       if let jsonString = String(data: data, encoding: .utf8) {
 //           print("--- RAW JSON RESPONSE for /v1/mobile/events ---")
 //           print("📄 [DEBUG] Purchase Records Raw JSON: \(jsonString)")
 //           print("--- END RAW JSON RESPONSE ---")
 //       }
 //       // --- END LOGGING BLOCK ---
        
        // DEBUG: Print raw JSON string for /events call
        if String(data: data, encoding: .utf8) != nil {
            // debug logging to disable for prod
            //           print("🎁 RAW JSON for /events (first ~2000 chars): \(String(jsonString.prefix(2000)))")
            do {
                _ = try JSONSerialization.jsonObject(with: data, options: []) as? [[String: Any]]
                // debug - disable in prod
                //    if let firstEventJSON = jsonArray?.first { // Log the first event object
             //       print("First Event Object from /events JSON: \(firstEventJSON)")
             //   }
            } catch { print("Could not parse /events JSON for detailed first object print.") }
        }
        // END DEBUG

        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ [NetworkManager] fetchEvents: Invalid response, not HTTP.")
            throw NetworkError.invalidResponse
        }

        print("🔄 [NetworkManager] fetchEvents: HTTP Status \(httpResponse.statusCode)")
        // if let responseBody = String(data: data, encoding: .utf8) {
        //     print("📦 [NetworkManager] fetchEvents: Response Body: \(responseBody)")
        // }

        if !(200...299).contains(httpResponse.statusCode) {
            let errorBody = String(data: data, encoding: .utf8) ?? "No error body"
            print("❌ [NetworkManager] fetchEvents: HTTP Error \(httpResponse.statusCode). Body: \(errorBody)")
            throw NetworkError.serverError("Failed to fetch events. Status: \(httpResponse.statusCode). \(errorBody)")
        }
        
        do {
            // Assuming API returns an array of Event objects directly
            // Use your configured decoder
            let fetchedEvents = try self.iso8601JSONDecoder.decode([Event].self, from: data)
            
            // <<< DETAILED DEBUG LOGGING for fetchedEvents >>>
            if fetchedEvents.isEmpty {
                print("‼️ [NetworkManager.fetchEvents] Decoding Succeeded but produced an EMPTY array of Events.")
            } else {
               print("✅ [NetworkManager.fetchEvents] Successfully decoded \(fetchedEvents.count) events.")
                // debug printing comment for prod
            //    for (index, event) in fetchedEvents.prefix(5).enumerated() { // Log first 5 events
             //       print("   Event \(index): ID=\(event.id), Title='\(event.title)'")
            //        print("     imageUrl: \(event.imageUrl ?? "NIL in decoded Event struct")")
            //        print("     isRegON: \(String(describing: event.isRegON))") // Use String(describing:) for Bool?
            //        print("     usesPanthi: \(String(describing: event.usesPanthi))")
            //        print("     date: \(String(describing: event.date))")
            //        print("     lastUpdatedAt: \(String(describing: event.lastUpdatedAt))")
            //    }
            }
            // <<< END DEBUG LOGGING >>>
            
            return (fetchedEvents, [])
        } catch {
            print("❌❌❌ [NetworkManager.fetchEvents] CRITICAL DECODING ERROR: \(error)") // More prominent error
            if let decodingError = error as? DecodingError {
                switch decodingError {
                case .typeMismatch(let type, let context):
                    print("TypeMismatch for \(type) at \(context.codingPath): \(context.debugDescription)")
                case .valueNotFound(let type, let context):
                    print("ValueNotFound for \(type) at \(context.codingPath): \(context.debugDescription)")
                case .keyNotFound(let key, let context):
                    print("KeyNotFound for \(key) at \(context.codingPath): \(context.debugDescription)")
                case .dataCorrupted(let context):
                    print("DataCorrupted at \(context.codingPath): \(context.debugDescription)")
                @unknown default:
                    print("Unknown decoding error.")
                }
            }
            throw NetworkError.decodingError(error)
        }
    }

    /// 1.1. Fetch sub-events for a specific parent event
    func fetchSubEvents(forParentEventId parentEventId: String) async throws -> [Event] {
        let url = eventsApiBaseURL.appendingPathComponent("events/\(parentEventId)/sub-events")
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        
        print("🚀 [NetworkManager] Fetching sub-events for parent event \(parentEventId)")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? "No error body"
            throw NetworkError.serverError("Failed to fetch sub-events. Status: \(httpResponse.statusCode). \(errorBody)")
        }
        
        do {
            let fetchedSubEvents = try self.iso8601JSONDecoder.decode([Event].self, from: data)
            print("✅ [NetworkManager] Successfully decoded \(fetchedSubEvents.count) sub-events.")
            return fetchedSubEvents
        } catch {
            print("❌ [NetworkManager] fetchSubEvents: Decoding failed: \(error)")
            throw NetworkError.decodingError(error)
        }
    }
    
    // 2. Fetch Ticket Types for a specific event
    func fetchTicketTypes(forEventId eventId: String) async throws -> [EventTicketType] {
        // Ensure eventId is properly URL encoded if it could contain special characters, though IDs usually don't.
        let url = eventsApiBaseURL.appendingPathComponent("events/\(eventId)/tickettypes")
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        // Add JWT token if required

 //       print("🚀 [NetworkManager] Fetching ticket types for event \(eventId) from: \(url.absoluteString)")

        let (data, response) = try await session.data(for: request)
        
        // DEBUG: Print raw JSON string for /events call
        if String(data: data, encoding: .utf8) != nil {
            // debug logging to disable for prod
           // print("🎁 RAW JSON for /events (first ~1000-2000 chars): \(String(jsonString.prefix(2000)))") // Print a decent chunk
            // You can also try to print the first few parsed objects if the string is too long
            do {
                let jsonArray = try JSONSerialization.jsonObject(with: data, options: []) as? [[String: Any]]
                if let firstFewEvents = jsonArray?.prefix(3) { // Log first 3 events
                    print("First few event objects from /events JSON: \(firstFewEvents)")
                }
            } catch { print("Could not parse /events JSON for detailed object print.") }
        }
        // END DEBUG

        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ [NetworkManager] fetchTicketTypes: Invalid response, not HTTP.")
            throw NetworkError.invalidResponse
        }
        
        print("🔄 [NetworkManager] fetchTicketTypes: HTTP Status \(httpResponse.statusCode)")

        if !(200...299).contains(httpResponse.statusCode) {
            let errorBody = String(data: data, encoding: .utf8) ?? "No error body"
            print("❌ [NetworkManager] fetchTicketTypes: HTTP Error \(httpResponse.statusCode). Body: \(errorBody)")
            throw NetworkError.serverError("Failed to fetch ticket types. Status: \(httpResponse.statusCode). \(errorBody)")
        }

        do {
            // Use your configured decoder
                return try self.iso8601JSONDecoder.decode([EventTicketType].self, from: data)
            
        } catch {
            print("❌ [NetworkManager] fetchTicketTypes: Decoding failed: \(error)")
            // Log more details for decoding errors
            if let decodingError = error as? DecodingError {
                switch decodingError {
                case .typeMismatch(let type, let context):
                    print("TypeMismatch for \(type) at \(context.codingPath): \(context.debugDescription)")
                case .valueNotFound(let type, let context):
                    print("ValueNotFound for \(type) at \(context.codingPath): \(context.debugDescription)")
                case .keyNotFound(let key, let context):
                    print("KeyNotFound for \(key) at \(context.codingPath): \(context.debugDescription)")
                case .dataCorrupted(let context):
                    print("DataCorrupted at \(context.codingPath): \(context.debugDescription)")
                @unknown default:
                    print("Unknown decoding error.")
                }
            }
            throw NetworkError.decodingError(error)
        }
    }

    // 3. Fetch Panthis for a specific event
    func fetchPanthis(forEventId eventId: String) async throws -> [Panthi] {
        let url = eventsApiBaseURL.appendingPathComponent("events/\(eventId)/panthis")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        // Add JWT token if required

        print("🚀 [NetworkManager] Fetching panthis for event \(eventId) from: \(url.absoluteString)")

        let (data, response) = try await session.data(for: request)
        
        // Optional: Add similar JSON logging here for Panthis if you encounter issues with it later
        if String(data: data, encoding: .utf8) != nil {
            // debug logging to disable for prod
            //  print("🎁 RAW JSON for /panthis (Event ID: \(eventId)): \(jsonString)")
         }

        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ [NetworkManager] fetchPanthis: Invalid response, not HTTP.")
            throw NetworkError.invalidResponse
        }
            
        print("🔄 [NetworkManager] fetchPanthis: HTTP Status \(httpResponse.statusCode)")

        if !(200...299).contains(httpResponse.statusCode) {
            let errorBody = String(data: data, encoding: .utf8) ?? "No error body"
            print("❌ [NetworkManager] fetchPanthis: HTTP Error \(httpResponse.statusCode). Body: \(errorBody)")
            throw NetworkError.serverError("Failed to fetch panthis. Status: \(httpResponse.statusCode). \(errorBody)")
        }
        
        do {
            return try self.iso8601JSONDecoder.decode([Panthi].self, from: data)
        } catch {
            print("❌ [NetworkManager] fetchPanthis: Decoding failed: \(error)")
            throw NetworkError.decodingError(error)
        }
    }
    // 4. Fetch Programs for a specific event
    func fetchPrograms(forEventId eventId: String) async throws -> [EventProgram] {
        let url = eventsApiBaseURL.appendingPathComponent("events/\(eventId)/programs")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("application/json", forHTTPHeaderField: "Accept")

        print("🚀 [NetworkManager] Fetching programs for event \(eventId) from: \(url.absoluteString)")

        // Use the specialized session with timeouts
        let (data, response) = try await programSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }
        
        if httpResponse.statusCode == 401 {
            DatabaseManager.shared.clearSession()
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .didSessionExpire, object: nil)
            }
            throw NetworkError.serverError("Authentication expired.")
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? "No error body"
            print("❌ [NetworkManager] fetchPrograms: HTTP Error \(httpResponse.statusCode). Body: \(errorBody)")
            throw NetworkError.serverError("Failed to fetch programs. Status: \(httpResponse.statusCode)")
        }

        do {
            return try self.iso8601JSONDecoder.decode([EventProgram].self, from: data)
        } catch {
            print("❌ [NetworkManager] fetchPrograms: Decoding failed: \(error)")
            throw NetworkError.decodingError(error)
        }
    }
    
    func getEligibleParticipants(forProgramId programId: String) async throws -> [FamilyMember] {
        guard let jwt = DatabaseManager.shared.jwtApiToken else {
            print("❌ [NetworkManager] getEligibleParticipants: JWT token is NIL. Throwing unauthenticated error.")
            throw NetworkError.serverError("User not authenticated.")
        }

        let url = baseURL.appendingPathComponent("v1/mobile/programs/\(programId)/eligible-participants")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")

        print("🚀 [NetworkManager] Fetching eligible participants for program \(programId) from URL: \(url.absoluteString)")

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                print("❌ [NetworkManager] getEligibleParticipants: Invalid response type")
                throw NetworkError.invalidResponse
            }

            print("📡 [NetworkManager] getEligibleParticipants: HTTP Status \(httpResponse.statusCode)")

            if httpResponse.statusCode == 401 {
                print("🔒 [NetworkManager] getEligibleParticipants: Unauthorized - clearing session")
                DatabaseManager.shared.clearSession()
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .didSessionExpire, object: nil)
                }
                throw NetworkError.serverError("Authentication expired. Please log in again.")
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                let errorBody = String(data: data, encoding: .utf8) ?? "No response body"
                print("❌ [NetworkManager] getEligibleParticipants: HTTP Error \(httpResponse.statusCode). Body: \(errorBody)")
                throw NetworkError.serverError("Failed to load eligible participants. Status: \(httpResponse.statusCode). \(errorBody)")
            }

            do {
                let decodedParticipants = try self.iso8601JSONDecoder.decode([FamilyMember].self, from: data)
                print("✅ [NetworkManager] Successfully decoded \(decodedParticipants.count) eligible participants.")
                return decodedParticipants
            } catch {
                print("❌ [NetworkManager] getEligibleParticipants: Decoding failed: \(error)")
                if let decodingError = error as? DecodingError {
                    switch decodingError {
                    case .typeMismatch(let type, let context):
                        print("TypeMismatch for \(type) at \(context.codingPath): \(context.debugDescription)")
                    case .valueNotFound(let type, let context):
                        print("ValueNotFound for \(type) at \(context.codingPath): \(context.debugDescription)")
                    case .keyNotFound(let key, let context):
                        print("KeyNotFound for \(key) at \(context.codingPath): \(context.debugDescription)")
                    case .dataCorrupted(let context):
                        print("DataCorrupted at \(context.codingPath): \(context.debugDescription)")
                    @unknown default:
                        print("Unknown decoding error.")
                    }
                }
                throw NetworkError.decodingError(error)
            }
        } catch let networkError as NetworkError {
            throw networkError
        } catch {
            print("❌ [NetworkManager] getEligibleParticipants: Network error: \(error)")
            throw NetworkError.serverError("Network error: \(error.localizedDescription)")
        }
    }
    
    func fetchPurchaseRecords(since: Date? = nil) async throws -> [PurchaseRecord] {
        guard let jwt = DatabaseManager.shared.jwtApiToken else {
            print("❌ [NetworkManager] fetchPurchaseRecords: JWT token is missing")
            throw NetworkError.serverError("User not authenticated. Please log in again.")
        }
        
        var urlComponents = URLComponents(url: baseURL.appendingPathComponent("v1/mobile/my-events"), resolvingAgainstBaseURL: false)!
        
        // If a 'since' date is provided, add it as a query parameter
        if let sinceDate = since {
            urlComponents.queryItems = [
                URLQueryItem(name: "since", value: ISO8601DateFormatter().string(from: sinceDate))
            ]
        }
        
        guard let url = urlComponents.url else {
            throw NetworkError.serverError("Could not create URL for records request.")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")

        print("🚀 [NetworkManager] Fetching purchase records from: \(url.absoluteString)")
        print("🔐 [NetworkManager] Using JWT token: \(jwt.prefix(20))...")

        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("❌ [NetworkManager] fetchPurchaseRecords: Invalid response type")
                throw NetworkError.invalidResponse
            }
            
            print("📡 [NetworkManager] fetchPurchaseRecords: HTTP Status \(httpResponse.statusCode)")
            
            if httpResponse.statusCode == 401 {
                print("🔒 [NetworkManager] fetchPurchaseRecords: Unauthorized - clearing session")
                DatabaseManager.shared.clearSession()
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .didSessionExpire, object: nil)
                }
                throw NetworkError.serverError("Authentication expired. Please log in again.")
            }
            
            guard (200...299).contains(httpResponse.statusCode) else {
                let errorBody = String(data: data, encoding: .utf8) ?? "No error body"
                print("❌ [NetworkManager] fetchPurchaseRecords: HTTP Error \(httpResponse.statusCode). Body: \(errorBody)")
                throw NetworkError.serverError("Failed to fetch records. Status: \(httpResponse.statusCode). \(errorBody)")
            }

            do {
                let records = try self.iso8601JSONDecoder.decode([PurchaseRecord].self, from: data)
                print("✅ [NetworkManager] fetchPurchaseRecords: Successfully decoded \(records.count) records")
                return records
            } catch {
                print("❌ [NetworkManager] fetchPurchaseRecords: Decoding failed: \(error)")
                if let responseString = String(data: data, encoding: .utf8) {
                    print("📄 [NetworkManager] Response body: \(responseString)")
                }
                throw NetworkError.decodingError(error)
            }
        } catch {
            if error is NetworkError {
                throw error
            } else {
                print("❌ [NetworkManager] fetchPurchaseRecords: Network error: \(error)")
                throw NetworkError.serverError("Network error: \(error.localizedDescription)")
            }
        }
    }

    func fetchTicketRecordDetail(id: Int) async throws -> TicketPurchaseDetailResponse {
        // Check if we already have an active request for this ID
        return try await withCheckedThrowingContinuation { continuation in
            requestQueue.async(flags: .barrier) {
                // If there's already an active request, wait for it
                if let existingTask = self.activeTicketRequests[id] {
                    Task {
                        do {
                            let result = try await existingTask.value
                            continuation.resume(returning: result)
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    }
                    return
                }
                
                // Create new request
                let task = Task {
                    defer {
                        self.requestQueue.async(flags: .barrier) {
                            self.activeTicketRequests.removeValue(forKey: id)
                        }
                    }
                    
                    guard let jwt = DatabaseManager.shared.jwtApiToken else {
                        print("❌ [NetworkManager] fetchTicketRecordDetail: JWT token is missing")
                        throw NetworkError.serverError("User not authenticated. Please log in again.")
                    }
                    
                    let url = self.baseURL.appendingPathComponent("v1/mobile/my-events/ticket/\(id)")
                    var request = URLRequest(url: url)
                    request.httpMethod = "GET"
                    request.addValue("application/json", forHTTPHeaderField: "Accept")
                    request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")

                    print("🚀 [NetworkManager] Fetching ticket detail for ID: \(id)")

                    do {
                        let (data, response) = try await self.session.data(for: request)

                        guard let httpResponse = response as? HTTPURLResponse else {
                            throw NetworkError.invalidResponse
                        }
                        
                        print("📡 [NetworkManager] fetchTicketRecordDetail: HTTP Status \(httpResponse.statusCode)")
                        
                        if httpResponse.statusCode == 401 {
                            DatabaseManager.shared.clearSession()
                            DispatchQueue.main.async {
                                NotificationCenter.default.post(name: .didSessionExpire, object: nil)
                            }
                            throw NetworkError.serverError("Authentication expired. Please log in again.")
                        }

                        guard (200...299).contains(httpResponse.statusCode) else {
                            throw NetworkError.serverError("Failed to fetch ticket details. Status: \(httpResponse.statusCode)")
                        }

                        do {
                            return try self.iso8601JSONDecoder.decode(TicketPurchaseDetailResponse.self, from: data)
                        } catch {
                            print("❌ [NetworkManager] fetchTicketRecordDetail: Decoding failed: \(error)")
                            throw NetworkError.decodingError(error)
                        }
                    } catch {
                        if error is NetworkError {
                            throw error
                        } else {
                            throw NetworkError.serverError("Network error: \(error.localizedDescription)")
                        }
                    }
                }
                
                self.activeTicketRequests[id] = task
                
                Task {
                    do {
                        let result = try await task.value
                        continuation.resume(returning: result)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }
    
    func fetchProgramRecordDetail(id: Int) async throws -> Participant {
        // Check if we already have an active request for this ID
        return try await withCheckedThrowingContinuation { continuation in
            requestQueue.async(flags: .barrier) {
                // If there's already an active request, wait for it
                if let existingTask = self.activeProgramRequests[id] {
                    Task {
                        do {
                            let result = try await existingTask.value
                            continuation.resume(returning: result)
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    }
                    return
                }
                
                // Create new request
                let task = Task {
                    defer {
                        self.requestQueue.async(flags: .barrier) {
                            self.activeProgramRequests.removeValue(forKey: id)
                        }
                    }
                    
                    guard let jwt = DatabaseManager.shared.jwtApiToken else {
                        print("❌ [NetworkManager] fetchProgramRecordDetail: JWT token is missing")
                        throw NetworkError.serverError("User not authenticated. Please log in again.")
                    }
                    
                    let url = self.baseURL.appendingPathComponent("v1/mobile/my-events/program/\(id)")
                    var request = URLRequest(url: url)
                    request.httpMethod = "GET"
                    request.addValue("application/json", forHTTPHeaderField: "Accept")
                    request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")

                    print("🚀 [NetworkManager] Fetching program detail for ID: \(id)")

                    do {
                        let (data, response) = try await self.session.data(for: request)

                        guard let httpResponse = response as? HTTPURLResponse else {
                            throw NetworkError.invalidResponse
                        }
                        
                        print("📡 [NetworkManager] fetchProgramRecordDetail: HTTP Status \(httpResponse.statusCode)")
                        
                        if httpResponse.statusCode == 401 {
                            DatabaseManager.shared.clearSession()
                            DispatchQueue.main.async {
                                NotificationCenter.default.post(name: .didSessionExpire, object: nil)
                            }
                            throw NetworkError.serverError("Authentication expired. Please log in again.")
                        }

                        guard (200...299).contains(httpResponse.statusCode) else {
                            throw NetworkError.serverError("Failed to fetch program details. Status: \(httpResponse.statusCode)")
                        }

                        do {
                            return try self.iso8601JSONDecoder.decode(Participant.self, from: data)
                        } catch {
                            print("❌ [NetworkManager] fetchProgramRecordDetail: Decoding failed: \(error)")
                            throw NetworkError.decodingError(error)
                        }
                    } catch {
                        if error is NetworkError {
                            throw error
                        } else {
                            throw NetworkError.serverError("Network error: \(error.localizedDescription)")
                        }
                    }
                }
                
                self.activeProgramRequests[id] = task
                
                Task {
                    do {
                        let result = try await task.value
                        continuation.resume(returning: result)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }
    
    func registerForProgram(eventId: String, programId: String, participantIds: [Int], practiceLocationId: Int? = nil, comments: String, guestParticipant: [String: Any]? = nil) async throws {
        guard let jwt = DatabaseManager.shared.jwtApiToken else {
            throw NetworkError.serverError("User not authenticated.")
        }
        
        let url = baseURL.appendingPathComponent("v1/mobile/events/\(eventId)/programs/\(programId)/register")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")

        var body: [String: Any] = [
            "participant_ids": participantIds,
            "comments": comments
        ]
        
        if let guest = guestParticipant {
            body["guest_participant"] = guest
        }
        
        // Include practice location if provided
        if let locationId = practiceLocationId {
            body["practice_location_id"] = locationId
        }
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        print("🚀 [NetworkManager] Submitting registration for program \(programId) with participants \(participantIds)")
        if let locationId = practiceLocationId {
            print("   Including practice location ID: \(locationId)")
        }

        let (data, response) = try await session.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse {
            print("DEBUG: [registerForProgram] HTTP Status: \(httpResponse.statusCode)")
            if let responseBody = String(data: data, encoding: .utf8) {
                print("DEBUG: [registerForProgram] Response Body (first 500 chars): \(String(responseBody.prefix(500)))")
            }
        } else {
            print("DEBUG: [registerForProgram] Response is not HTTPURLResponse. Type: \(type(of: response))")
        }

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? "No response body"
            print("❌ [NetworkManager] registerForProgram: HTTP Error. Body: \(errorBody)")
            throw NetworkError.serverError("Failed to submit registration. Status: \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }
        print("✅ [NetworkManager] Successfully submitted registration for program \(programId).")
    }

    func withdrawProgramRegistration(participantId: Int) async throws -> WithdrawResponse {
        guard let jwt = DatabaseManager.shared.jwtApiToken else {
            throw NetworkError.serverError("User not authenticated.")
        }

        let url = baseURL.appendingPathComponent("v1/mobile/my-events/program/\(participantId)/withdraw")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")

        print("🚀 [NetworkManager] Withdrawing program registration ID: \(participantId)")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }

        print("📡 [NetworkManager] withdrawProgramRegistration: HTTP Status \(httpResponse.statusCode)")

        if httpResponse.statusCode == 401 {
            DatabaseManager.shared.clearSession()
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .didSessionExpire, object: nil)
            }
            throw NetworkError.serverError("Authentication expired. Please log in again.")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            // Try to parse error message from response
            if let errorResponse = try? JSONDecoder().decode([String: String].self, from: data),
               let errorMessage = errorResponse["error"] {
                throw NetworkError.serverError(errorMessage)
            }
            throw NetworkError.serverError("Failed to withdraw registration. Status: \(httpResponse.statusCode)")
        }

        // Decode response
        let withdrawResponse = try JSONDecoder().decode(WithdrawResponse.self, from: data)
        print("✅ [NetworkManager] Program registration withdrawn successfully. Refund required: \(withdrawResponse.refund_required)")

        return withdrawResponse
    }

    func processRefund(participantId: Int, amount: Double, saleId: String) async throws -> RefundResponse {
        guard let jwt = DatabaseManager.shared.jwtApiToken else {
            throw NetworkError.serverError("User not authenticated.")
        }

        let url = baseURL.appendingPathComponent("v1/mobile/programs/refund")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "participant_id": participantId,
            "amount": amount,
            "sale_id": saleId
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        print("🚀 [NetworkManager] Processing refund for participant \(participantId), amount: $\(amount)")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }

        print("📡 [NetworkManager] processRefund: HTTP Status \(httpResponse.statusCode)")

        if httpResponse.statusCode == 401 {
            DatabaseManager.shared.clearSession()
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .didSessionExpire, object: nil)
            }
            throw NetworkError.serverError("Authentication expired. Please log in again.")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if let errorResponse = try? JSONDecoder().decode([String: String].self, from: data),
               let errorMessage = errorResponse["error"] {
                throw NetworkError.serverError(errorMessage)
            }
            throw NetworkError.serverError("Failed to process refund. Status: \(httpResponse.statusCode)")
        }

        let refundResponse = try JSONDecoder().decode(RefundResponse.self, from: data)
        print("✅ [NetworkManager] Refund processed successfully: \(refundResponse.refund_status)")

        return refundResponse
    }

    // MARK: - Response Models
    struct WithdrawResponse: Codable {
        let success: Bool
        let message: String
        let refund_required: Bool
        let refund_data: RefundData?
    }

    struct RefundData: Codable {
        let amount: Double
        let sale_id: String
        let participant_id: Int
    }

    struct RefundResponse: Codable {
        let success: Bool
        let message: String
        let refund_status: String
        let refund_id: String
        let refund_amount: Double
    }

    /// Generic JSON POST/GET helper, retries once on 401
    private func performRequest(
        _ request: URLRequest,
        retrying: Bool = true,
        completion: @escaping (Result<Data, NetworkError>) -> Void
    ) {
        session.dataTask(with: request) { data, resp, err in
            if let e = err {
                print("⚠️ [NetworkManager] Transport error: \(e.localizedDescription)")
                return DispatchQueue.main.async {
                    completion(.failure(.serverError(e.localizedDescription)))
                }
            }
            
            guard let http = resp as? HTTPURLResponse else {
                print("⚠️ [NetworkManager] Non-HTTP response")
                return DispatchQueue.main.async {
                    completion(.failure(.invalidResponse))
                }
            }
            
            // Enhanced 401 handling
            if http.statusCode == 401 && retrying {
                print("🔄 [NetworkManager] Got 401, attempting token refresh...")
                return self.refreshToken { result in
                    switch result {
                    case .success(let newToken):
                        // Retry the original request with new token
                        var newReq = request
                        newReq.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
                        self.performRequest(newReq, retrying: false, completion: completion)
                    case .failure(let refreshError):
                        print("❌ [NetworkManager] Token refresh failed: \(refreshError)")
                        DispatchQueue.main.async {
                            completion(.failure(refreshError))
                        }
                    }
                }
            }
            
            // Handle successful responses
            guard (200..<300).contains(http.statusCode) else {
                let bodyText = data.flatMap { String(data: $0, encoding: .utf8) } ?? "No response body"
                print("⚠️ [NetworkManager] HTTP \(http.statusCode): \(bodyText)")
                
                // Special handling for authentication-related errors
                if http.statusCode == 401 || http.statusCode == 403 {
                    DispatchQueue.main.async {
                        DatabaseManager.shared.clearSession()
                        NotificationCenter.default.post(name: .didSessionExpire, object: nil)
                        completion(.failure(.serverError("Authentication failed. Please log in again.")))
                    }
                    return
                }
                
                return DispatchQueue.main.async {
                    completion(.failure(.serverError("HTTP \(http.statusCode)")))
                }
            }
            
            // Data must exist
            guard let d = data else {
                print("⚠️ [NetworkManager] HTTP \(http.statusCode) but no data")
                return DispatchQueue.main.async {
                    completion(.failure(.invalidResponse))
                }
            }
            
            DispatchQueue.main.async {
                completion(.success(d))
            }
        }
        .resume()
    }
    
    /// POST `/refresh-token`
    private func refreshToken(completion: @escaping (Result<String, NetworkError>) -> Void) {
        guard let refresh = DatabaseManager.shared.refreshToken else {
            print("⚠️ [NetworkManager] No refresh token available, clearing session")
            DatabaseManager.shared.clearSession()
            NotificationCenter.default.post(name: .didSessionExpire, object: nil)
            return completion(.failure(.invalidResponse))
        }
        
        let endpoint = baseURL.appendingPathComponent("refresh-token") // Keep existing path
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONEncoder().encode(["refreshToken": refresh])
        
        print("🔄 [NetworkManager] Attempting token refresh...")
        
        session.dataTask(with: req) { data, resp, err in
            if let e = err {
                print("❌ [NetworkManager] Token refresh network error: \(e.localizedDescription)")
                return DispatchQueue.main.async {
                    completion(.failure(.serverError(e.localizedDescription)))
                }
            }
            
            guard let http = resp as? HTTPURLResponse else {
                print("❌ [NetworkManager] Token refresh: Invalid response type")
                return DispatchQueue.main.async {
                    completion(.failure(.invalidResponse))
                }
            }
            
            print("🔄 [NetworkManager] Token refresh response status: \(http.statusCode)")
            
            // Handle different status codes
            if http.statusCode == 401 || http.statusCode == 422 {
                // Refresh token is expired or invalid
                print("🚫 [NetworkManager] Refresh token expired/invalid, forcing re-login")
                DispatchQueue.main.async {
                    DatabaseManager.shared.clearSession()
                    NotificationCenter.default.post(name: .didSessionExpire, object: nil)
                    completion(.failure(.serverError("Session expired. Please log in again.")))
                }
                return
            }
            
            guard (200..<300).contains(http.statusCode), let bytes = data else {
                let errorBody = data.flatMap { String(data: $0, encoding: .utf8) } ?? "No response body"
                print("❌ [NetworkManager] Token refresh failed with status \(http.statusCode): \(errorBody)")
                return DispatchQueue.main.async {
                    completion(.failure(.serverError("Token refresh failed: \(http.statusCode)")))
                }
            }
            
            do {
                let decoded = try self.iso8601JSONDecoder.decode(RefreshResponse.self, from: bytes)
                DatabaseManager.shared.saveJwtApiToken(decoded.token)
                DatabaseManager.shared.saveRefreshToken(decoded.refreshToken)
                print("✅ [NetworkManager] Token refresh successful")
                DispatchQueue.main.async {
                    completion(.success(decoded.token))
                }
            } catch {
                print("❌ [NetworkManager] Token refresh decode error: \(error)")
                DispatchQueue.main.async {
                    completion(.failure(.decodingError(error)))
                }
            }
        }
        .resume()
    }
    
    /// JSON POST `v1/user/create`
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
        selectedMembershipId: String,
        captchaToken: String,
        completion: @escaping (Result<(token: String, user: UserProfile), NetworkError>) -> Void
    ) {
        let endpoint = baseURL.appendingPathComponent("v1/user/create")
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var body: [String: Any] = [
            "name": name,
            "phone": phone,
            "email": email,
            "address": address,
            "password": password,
            "password_confirmation": confirmPassword,
            "memb_pckg": selectedMembershipId
        ]
        
        if let spouseName = spouseName, !spouseName.isEmpty {
            body["spouse_name"] = spouseName
        }
        if let spouseEmail = spouseEmail, !spouseEmail.isEmpty {
            body["spouse_email"] = spouseEmail
        }
        
        req.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [])
        
        session.dataTask(with: req) { data, resp, err in
            if let e = err {
                DispatchQueue.main.async {
                    completion(.failure(.serverError(e.localizedDescription)))
                }
                return
            }
            
            guard let http = resp as? HTTPURLResponse, let bytes = data else {
                DispatchQueue.main.async {
                    completion(.failure(.invalidResponse))
                }
                return
            }
            
            if !(200..<300).contains(http.statusCode) {
                // Preserve existing logging:
                let bodyText = String(data: bytes, encoding: .utf8) ?? "No response"
                print("⚠️ [Registration Error] HTTP \(http.statusCode): \(bodyText)")
                
                // ✅ Add Laravel Validation error parsing:
                if http.statusCode == 422 {
                    do {
                        // Attempt to parse the JSON error structure: {"error":{"field":["message"]}}
                        if let errorJson = try JSONSerialization.jsonObject(with: bytes, options: []) as? [String: Any],
                           // PRECISION UPDATE: Change "errors" to "error" to match your backend response
                           let errorDetailDict = errorJson["error"] as? [String: [String]] {
                            
                            // Consolidate all error messages
                            let messages = errorDetailDict.flatMap { $0.value }.joined(separator: "\n")
                            DispatchQueue.main.async {
                                completion(.failure(.serverError(messages.isEmpty ? "Validation failed. Please check your input." : messages)))
                            }
                        } else {
                            // If parsing the specific error structure fails, return a generic validation error or the bodyText
                            DispatchQueue.main.async {
                                completion(.failure(.serverError("Validation error. Details: \(bodyText)")))
                            }
                        }
                    } catch {
                        // If JSONSerialization itself fails
                        DispatchQueue.main.async {
                            completion(.failure(.serverError("Could not parse validation error response. Body: \(bodyText)")))
                        }
                    }
                } else {
                    // For other non-2xx, non-422 errors
                    DispatchQueue.main.async {
                        completion(.failure(.serverError("Server error: \(http.statusCode). \(bodyText)")))
                    }
                }
                return
            }
            
            // Successful registration (2xx)
            do {
                let loginResp = try self.iso8601JSONDecoder.decode(LoginResponse.self, from: bytes)
                DatabaseManager.shared.saveJwtApiToken(loginResp.token)
                DatabaseManager.shared.saveRefreshToken(loginResp.refreshToken)
                
                self.fetchProfileJSON { result in
                    DispatchQueue.main.async {
                        switch result {
                        case .success(let profile):
                            DatabaseManager.shared.saveUser(profile)
                            UserDefaults.standard.set(profile.id, forKey: "userId")
                            completion(.success((token: loginResp.token, user: profile)))
                        case .failure(let err):
                            // Successful registration but failed to fetch profile immediately after
                            completion(.failure(err))
                        }
                    }
                }
            } catch {
                // This catch is for failure to decode LoginResponse on a 2xx status
                DispatchQueue.main.async {
                    let responseBody = String(data: bytes, encoding: .utf8) ?? "No data"
                    print("❌ [Registration Success Decode Error] Failed to decode LoginResponse. Body: \(responseBody). Error: \(error)")
                    completion(.failure(.decodingError(error)))
                }
            }
        }.resume()
    }
}
// MARK: – Trust & Redirects for loginSession
extension NetworkManager: URLSessionDelegate, URLSessionTaskDelegate {

    // Trust the test cert unconditionally - but comment in production use
//    func urlSession(_ session: URLSession,
//                    didReceive challenge: URLAuthenticationChallenge,
//                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void)
//    {
//        let host = challenge.protectionSpace.host
//        if host == "nemausa.org",
//           let trust = challenge.protectionSpace.serverTrust
//        {
//            completionHandler(.useCredential, URLCredential(trust: trust))
//        } else {
//            completionHandler(.performDefaultHandling, nil)
//        }
//    }

    // Prevent redirects on our loginSession so we can see the 302
    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void)
    {
       if session == self.loginSession {
            completionHandler(nil)
        } else {
            completionHandler(request)
        }
    }
} // end of file
