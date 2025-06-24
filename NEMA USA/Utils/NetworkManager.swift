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
    
    /// Scrape `/profile` HTML → UserProfile
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
    
    /// Scrape `/fmly_mmbr` HTML → [FamilyMember]
    func fetchFamily(completion: @escaping (Result<[FamilyMember], NetworkError>) -> Void) {
        guard DatabaseManager.shared.laravelSessionToken != nil else {
            return completion(.failure(.invalidResponse))
        }
        let url = baseURL.appendingPathComponent("fmly_mmbr")
        session.dataTask(with: url) { data, _, err in
            if let err = err {
                return DispatchQueue.main.async {
                    completion(.failure(.serverError(err.localizedDescription)))
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
                let doc = try SwiftSoup.parse(html)
                guard let container = try doc
                    .select("div.register-form ul.mt-3.row")
                    .first()
                else {
                    throw NSError(domain: "Parse", code: 0,
                                  userInfo: [NSLocalizedDescriptionKey: "Family list not found"])
                }
                
                var members = [FamilyMember]()
                let nameEls = try container.select("h5.col-9")
                for nameEl in nameEls {
                    let name = try nameEl.text()
                    guard
                        let span   = try nameEl.nextElementSibling(),
                        let anchor = try span.select("a").first(),
                        let rawHref = try? anchor.attr("href"),
                        let comps   = URLComponents(string: rawHref),
                        let idQuery = comps.queryItems?.first(where: { $0.name == "id" })?.value,
                        let id      = Int(idQuery)
                    else {
                        continue
                    }
                    
                    let detailsUl = try span.nextElementSibling()
                    let lis       = try detailsUl?.select("li") ?? Elements()
                    
                    var relVal: String?
                    var emailVal: String?
                    var dobVal: String?
                    var phoneVal: String?
                    
                    for li in lis {
                        let txt   = try li.text()
                        let parts = txt
                            .split(separator: ":", maxSplits: 1)
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                        guard parts.count == 2 else { continue }
                        switch parts[0].lowercased() {
                        case "relationship": relVal   = parts[1].isEmpty ? nil : parts[1]
                        case "email":        emailVal = parts[1].isEmpty ? nil : parts[1]
                        case "dob":          dobVal   = parts[1].isEmpty ? nil : parts[1]
                        case "phone":        phoneVal = parts[1].isEmpty ? nil : parts[1]
                        default: break
                        }
                    }
                    
                    members.append(.init(
                        id:           id,
                        name:         name,
                        relationship: relVal   ?? "",
                        email:        emailVal,
                        dob:          dobVal,
                        phone:        phoneVal
                    ))
                }
                
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
        completion: @escaping (Result<UserProfile, NetworkError>) -> Void
    ) {
        fetchCSRFToken { result in
            switch result {
            case .failure:
                return completion(.failure(.invalidResponse))
            case .success(let token):
                var req = URLRequest(url: self.baseURL.appendingPathComponent("profile"))
                req.httpMethod = "POST"
                req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
                
                let userId = DatabaseManager.shared.currentUser?.id ?? 0
                let params = [
                    "_token": token,
                    "user_id": String(userId),
                    "name": name,
                    "phone": phone,
                    "address": address
                ]
                req.httpBody = params
                    .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)" }
                    .joined(separator: "&")
                    .data(using: .utf8)
                
                self.session.dataTask(with: req) { data, resp, err in
                    if let err = err {
                        return DispatchQueue.main.async {
                            completion(.failure(.serverError(err.localizedDescription)))
                        }
                    }
                    guard let http = resp as? HTTPURLResponse,
                          (200..<400).contains(http.statusCode)
                    else {
                        let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? "No data"
                        print("⚠️ Update Profile Error, status: \(String(describing: resp)), body: \(body)")
                        return DispatchQueue.main.async {
                            completion(.failure(.invalidResponse))
                        }
                    }
                    
                    // 3) now fetch the *JSON* user — this has the full profile + expiry
                    self.fetchProfileJSON { result in
                        DispatchQueue.main.async {
                            switch result {
                            case .success(let freshProfile):
                                completion(.success(freshProfile))
                                
                            case .failure(let err):
                                completion(.failure(err))
                            }
                        }
                    }
                }
                .resume()
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
    
    /// Adds a new family member using a form-POST to the /fmly_mmbr endpoint.
    func addNewFamilyMember(
        name: String,
        relationship: String,
        email: String?,
        dob: String?, // Expected format "YYYY-MM"
        phone: String?,
        completion: @escaping (Result<Void, NetworkError>) -> Void
    ) {
        fetchCSRFToken { result in
            switch result {
            case .failure(let error):
                DispatchQueue.main.async {
                    completion(.failure(.serverError("CSRF token fetch failed for add member: \(error.localizedDescription)")))
                }
            case .success(let token):
                let addURL = self.baseURL.appendingPathComponent("fmly_mmbr") // Same URL as updateFamily
                var req = URLRequest(url: addURL)
                req.httpMethod = "POST"
                req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
                req.setValue("\(self.baseURL)/fmly_mmbr", forHTTPHeaderField: "Referer") // Consistent referer

                var params: [String: String] = [
                    "_token":       token,
                    "fname":        name,
                    "relationship": relationship
                ]
                // Add optional fields only if they have values
                if let email = email, !email.isEmpty { params["email"] = email }
                if let phone = phone, !phone.isEmpty { params["phone"] = phone }
                if let dob = dob, !dob.isEmpty { params["dob"] = dob }
                // IMPORTANT: DO NOT send an "id" parameter for new members,
                // as per UserController.php's addListFamilyMember logic and HAR analysis.

                req.httpBody = params
                    .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)" }
                    .joined(separator: "&")
                    .data(using: .utf8)

                print("🚀 [NetworkManager] Adding new family member: \(name) to URL: \(addURL.absoluteString) with params: \(params)")

                self.session.dataTask(with: req) { data, resp, err in
                    if let e = err {
                        DispatchQueue.main.async {
                            completion(.failure(.serverError("Add new member request failed: \(e.localizedDescription)")))
                        }
                        return
                    }
                    guard let http = resp as? HTTPURLResponse else {
                        DispatchQueue.main.async {
                            completion(.failure(.invalidResponse))
                        }
                        return
                    }

                    // Successful form POSTs for add/update usually result in a redirect (302)
                    // or a 200 if the page is re-rendered with messages.
                    if (200..<400).contains(http.statusCode) {
                        print("✅ [NetworkManager] Add new member request processed by backend (Status: \(http.statusCode)).")
                        DispatchQueue.main.async {
                            completion(.success(()))
                        }
                    } else {
                        let responseBody = data.flatMap { String(data: $0, encoding: .utf8) } ?? "No response body"
                        print("⚠️ Add New Family Member Error, status: \(http.statusCode), body: \(responseBody)")
                        DispatchQueue.main.async {
                            completion(.failure(.serverError("Add new member failed on server with status \(http.statusCode).")))
                        }
                    }
                }.resume()
            }
        }
    }

    /// POST `/fmly_mmbr` form-URL-encoded (one request per member)
    func updateFamily(
        _ members: [FamilyMember],
        completion: @escaping (Result<Void, NetworkError>) -> Void
    ) {
        fetchCSRFToken { result in
            switch result {
            case .failure:
                return completion(.failure(.invalidResponse))
            case .success(let token):
                let group = DispatchGroup()
                var anyError: NetworkError?
                
                for m in members {
                    group.enter()
                    var req = URLRequest(url: self.baseURL.appendingPathComponent("fmly_mmbr"))
                    req.httpMethod = "POST"
                    req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
                    
                    let params: [String: String] = [
                        "_token":       token,
                        "fname":        m.name,
                        "email":        m.email    ?? "",
                        "phone":        m.phone    ?? "",
                        "dob":          m.dob      ?? "",
                        "relationship": m.relationship,
                        "id":           String(m.id)
                    ]
                    req.httpBody = params
                        .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)" }
                        .joined(separator: "&")
                        .data(using: .utf8)
                    
                    self.session.dataTask(with: req) { _, resp, err in
                        if let err = err {
                            anyError = .serverError(err.localizedDescription)
                        } else if let http = resp as? HTTPURLResponse, !(200..<400).contains(http.statusCode) {
                            anyError = .invalidResponse
                        }
                        group.leave()
                    }
                    .resume()
                }
                
                group.notify(queue: .main) {
                    if let err = anyError {
                        completion(.failure(err))
                    } else {
                        completion(.success(()))
                    }
                }
            }
        }
    }
    
    /// Deletes a family member using a form-POST, consistent with fmly_mmbr interactions.
    func deleteFamilyMember(
        memberId: Int,
        completion: @escaping (Result<Void, NetworkError>) -> Void
    ) {
        // For GET requests, CSRF tokens are generally not used or checked by Laravel by default.
        // Parameters will be part of the URL.
        
        var urlComponents = URLComponents(url: self.baseURL.appendingPathComponent("family/delete"), resolvingAgainstBaseURL: false)!
        urlComponents.queryItems = [
            URLQueryItem(name: "id", value: String(memberId)) // Send 'id' as a query parameter
        ]

        guard let deleteURL = urlComponents.url else {
            DispatchQueue.main.async {
                completion(.failure(.serverError("Could not construct delete URL for GET request.")))
            }
            return
        }

        var req = URLRequest(url: deleteURL)
        req.httpMethod = "GET" // Changed from POST to GET

        // Headers for POST (like Content-Type for form-urlencoded) are not needed for GET.
        // The Referer header might still be useful for some web servers/analytics, so it can be kept if desired,
        // but it's not strictly necessary for the GET request itself to function.
        // req.setValue("\(self.baseURL)/fmly_mmbr", forHTTPHeaderField: "Referer") // Optional: keep if needed

        print("🚀 [NetworkManager] Deleting family member ID (GET): \(memberId) from URL: \(deleteURL.absoluteString)")

        // Use self.session, which handles cookies (important for web routes)
        self.session.dataTask(with: req) { data, resp, err in
            if let e = err {
                DispatchQueue.main.async {
                    completion(.failure(.serverError("Delete request (GET) failed: \(e.localizedDescription)")))
                }
                return
            }
            guard let http = resp as? HTTPURLResponse else {
                DispatchQueue.main.async {
                    completion(.failure(.invalidResponse))
                }
                return
            }

            // A successful GET to a web route that performs an action and then redirects
            // (like your PHP's `return redirect()->route('fmly_mmbr');`)
            // will typically result in a 302 (redirect) status from the initial GET request if successful,
            // or a 200 if the server processes the delete and then re-renders the destination page directly
            // in the response to this GET.
            // The URLSession will automatically follow the 302 redirect by default and the final status (e.g. 200 for the fmly_mmbr page)
            // will be what 'http.statusCode' reflects here, unless redirect handling is customized.
            // We'll consider 200-399 as success because the redirect itself implies the action was likely processed.
            if (200..<400).contains(http.statusCode) {
                DispatchQueue.main.async {
                    print("✅ [NetworkManager] Delete request (GET) for family member ID: \(memberId) processed. Final status: \(http.statusCode).")
                    completion(.success(()))
                }
            } else {
                let responseBody = data.flatMap { String(data: $0, encoding: .utf8) } ?? "No response body"
                print("⚠️ Delete Family Member via GET Error, status: \(http.statusCode), body: \(responseBody)")
                DispatchQueue.main.async {
                    completion(.failure(.serverError("Delete failed on server (GET) with status \(http.statusCode).")))
                }
            }
        }.resume()
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

    // 2. Fetch Ticket Types for a specific event
    func fetchTicketTypes(forEventId eventId: String) async throws -> [EventTicketType] {
        // Ensure eventId is properly URL encoded if it could contain special characters, though IDs usually don't.
        let url = eventsApiBaseURL.appendingPathComponent("events/\(eventId)/tickettypes")
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        // Add JWT token if required

        print("🚀 [NetworkManager] Fetching ticket types for event \(eventId) from: \(url.absoluteString)")

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

        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? "No error body"
            print("❌ [NetworkManager] fetchPrograms: HTTP Error. Body: \(errorBody)")
            throw NetworkError.serverError("Failed to fetch programs. Status: \((response as? HTTPURLResponse)?.statusCode ?? 0)")
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
            print("DEBUG: [getEligibleParticipants] JWT token is NIL. Throwing unauthenticated error.")
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

            // ADD THESE DEBUG PRINTS (make sure they are not commented out):
            if let httpResponse = response as? HTTPURLResponse {
                print("DEBUG: [getEligibleParticipants] HTTP Status: \(httpResponse.statusCode)")
                if let responseBody = String(data: data, encoding: .utf8) {
                    print("DEBUG: [getEligibleParticipants] Response Body (first 500 chars): \(String(responseBody.prefix(500)))")
                }
            } else {
                print("DEBUG: [getEligibleParticipants] Response is not HTTPURLResponse. Type: \(type(of: response))")
            }

            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                let errorBody = String(data: data, encoding: .utf8) ?? "No response body"
                print("❌ [NetworkManager] getEligibleParticipants: HTTP Error. Status: \((response as? HTTPURLResponse)?.statusCode ?? 0). Body: \(errorBody)")
                throw NetworkError.serverError("Failed to fetch eligible participants. Status: \((response as? HTTPURLResponse)?.statusCode ?? 0). Error Body: \(errorBody)")
            }

            let decodedParticipants = try self.iso8601JSONDecoder.decode([FamilyMember].self, from: data)
            print("✅ [NetworkManager] Successfully decoded \(decodedParticipants.count) eligible participants.")
            // Optional: Print first few decoded participants for verification
            // for (index, member) in decodedParticipants.prefix(3).enumerated() {
            //    print("   Participant \(index): ID=\(member.id), Name=\(member.name)")
            // }
            return decodedParticipants
        } catch {
            print("❌ [NetworkManager] getEligibleParticipants: Caught decoding/network error: \(error)")
            // Ensure that NetworkError.decodingError also has full details
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
                throw NetworkError.decodingError(error) // Re-throw the structured error
            } else {
                throw error // Re-throw other errors (e.g., URLSession errors)
            }
        }
    }
    func fetchPurchaseRecords(since: Date? = nil) async throws -> [PurchaseRecord] { // Add 'since' parameter
        guard let jwt = DatabaseManager.shared.jwtApiToken else {
            throw NetworkError.serverError("User not authenticated.")
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

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? "No error body"
            throw NetworkError.serverError("Failed to fetch records. Status: \((response as? HTTPURLResponse)?.statusCode ?? 0). \(errorBody)")
        }

        do {
            return try self.iso8601JSONDecoder.decode([PurchaseRecord].self, from: data)
        } catch {
            print("❌ [NetworkManager] fetchPurchaseRecords: Decoding failed: \(error)")
            throw NetworkError.decodingError(error)
        }
    }

    func fetchTicketRecordDetail(id: Int) async throws -> TicketPurchaseDetailResponse {
        guard let jwt = DatabaseManager.shared.jwtApiToken else { throw NetworkError.serverError("User not authenticated.") }
        
        let url = baseURL.appendingPathComponent("v1/mobile/my-events/ticket/\(id)")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw NetworkError.serverError("Failed to fetch ticket details.")
        }

        do {
            return try self.iso8601JSONDecoder.decode(TicketPurchaseDetailResponse.self, from: data)
        } catch {
            print("❌ [NetworkManager] fetchTicketRecordDetail: Decoding failed: \(error)")
            throw NetworkError.decodingError(error)
        }
    }

    func fetchProgramRecordDetail(id: Int) async throws -> Participant {
        guard let jwt = DatabaseManager.shared.jwtApiToken else { throw NetworkError.serverError("User not authenticated.") }
        
        let url = baseURL.appendingPathComponent("v1/mobile/my-events/program/\(id)")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw NetworkError.serverError("Failed to fetch program details.")
        }

        do {
            return try self.iso8601JSONDecoder.decode(Participant.self, from: data)
        } catch {
            print("❌ [NetworkManager] fetchProgramRecordDetail: Decoding failed: \(error)")
            throw NetworkError.decodingError(error)
        }
    }
    
    func registerForProgram(eventId: String, programId: String, participantIds: [Int], comments: String) async throws {
        guard let jwt = DatabaseManager.shared.jwtApiToken else {
            throw NetworkError.serverError("User not authenticated.")
        }
        
        let url = baseURL.appendingPathComponent("v1/mobile/events/\(eventId)/programs/\(programId)/register")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "participant_ids": participantIds,
            "comments": comments
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        print("🚀 [NetworkManager] Submitting registration for program \(programId) with participants \(participantIds)")

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
        
        // This line was causing a decoding error if the API doesn't return FamilyMember array for registration
        // let decodedParticipants = try self.iso8601JSONDecoder.decode([FamilyMember].self, from: data)
        print("✅ [NetworkManager] Successfully submitted registration for program \(programId).")
    }

    /// Generic JSON POST/GET helper, retries once on 401
    private func performRequest(
        _ request: URLRequest,
        retrying: Bool = true,
        completion: @escaping (Result<Data, NetworkError>) -> Void
    ) {
        session.dataTask(with: request) { data, resp, err in
            // transport error
            if let e = err {
                print("⚠️ [NetworkManager] transport error:", e.localizedDescription)
                return DispatchQueue.main.async {
                    completion(.failure(.serverError(
                        "\(e.localizedDescription). Please check your connection."
                    )))
                }
            }
            // must be HTTP
            guard let http = resp as? HTTPURLResponse else {
                print("⚠️ [NetworkManager] non-HTTP response:", resp ?? "nil")
                return DispatchQueue.main.async {
                    completion(.failure(.serverError("Unexpected response format.")))
                }
            }
            // retry on 401…
            if http.statusCode == 401, retrying {
                return self.refreshToken { result in
                    switch result {
                    case .success(let newToken):
                        var newReq = request
                        newReq.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
                        self.performRequest(newReq, retrying: false, completion: completion)
                    case .failure:
                        DispatchQueue.main.async {
                            DatabaseManager.shared.clearSession()
                            NotificationCenter.default.post(name: .didSessionExpire, object: nil)
                            completion(.failure(.invalidResponse))
                        }
                    }
                }
            }
            // non-2xx? log status + body
            guard (200..<300).contains(http.statusCode) else {
                let bodyText = data.flatMap { String(data: $0, encoding: .utf8) } ?? "<no body>"
                print("⚠️ [NetworkManager] HTTP \(http.statusCode) →", bodyText)
                return DispatchQueue.main.async {
                    completion(.failure(.serverError("HTTP \(http.statusCode)")))
                }
            }
            // data must exist
            guard let d = data else {
                print("⚠️ [NetworkManager] HTTP \(http.statusCode) but no data")
                return DispatchQueue.main.async {
                    completion(.failure(.invalidResponse))
                }
            }
            DispatchQueue.main.async { completion(.success(d)) }
        }
        .resume()
    }
    
    /// POST `/refresh-token`
    private func refreshToken(completion: @escaping (Result<String, NetworkError>) -> Void) {
        guard let refresh = DatabaseManager.shared.refreshToken else {
            return completion(.failure(.invalidResponse))
        }
        let endpoint = baseURL.appendingPathComponent("refresh-token")
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONEncoder().encode(["refreshToken": refresh])
        
        session.dataTask(with: req) { data, resp, err in
            if let e = err {
                return DispatchQueue.main.async {
                    completion(.failure(.serverError(
                        "\(e.localizedDescription). Please check your network."
                    )))
                }
            }
            guard let http  = resp as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  let bytes = data
            else {
                return DispatchQueue.main.async {
                    completion(.failure(.invalidResponse))
                }
            }
            do {
                let decoded = try self.iso8601JSONDecoder.decode(RefreshResponse.self, from: bytes)
                DatabaseManager.shared.saveJwtApiToken(decoded.token)
                DatabaseManager.shared.saveRefreshToken(decoded.refreshToken)
                DispatchQueue.main.async { completion(.success(decoded.token)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(.decodingError(error))) }
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
