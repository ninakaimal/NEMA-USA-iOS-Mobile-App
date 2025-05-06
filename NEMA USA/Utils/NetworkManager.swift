//
//  NetworkManager.swift
//  NEMA USA
//  Created by Sajith on 4/20/25.
//  Updated for token-refresh on 4/22/25.
//  Added updateFamily on 5/10/25.
//

import Foundation
import SwiftSoup

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
    let user: UserProfile
}

private struct RefreshResponse: Decodable {
    let token: String
    let refreshToken: String
}

/// A delegate to unconditionally trust the test.nemausa.org cert
class InsecureTrustDelegate: NSObject, URLSessionDelegate {
    func urlSession(_ session: URLSession,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void)
    {
        let host = challenge.protectionSpace.host
        if host == "test.nemausa.org",
           let trust = challenge.protectionSpace.serverTrust
        {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
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
      let url = URL(string: "https://nema-api.kanakaagro.in/api/login")!
      var req = URLRequest(url: url)
      req.httpMethod = "POST"
      req.addValue("application/json", forHTTPHeaderField: "Content-Type")
      let body = ["email": email, "password": password]
      req.httpBody = try? JSONEncoder().encode(body)

      session.dataTask(with: req) { data, resp, err in
        // transport error
        if let e = err {
          print("⚠️ [NetworkManager] loginJSON transport error:", e.localizedDescription)
          return DispatchQueue.main.async {
            completion(.failure(.serverError(e.localizedDescription)))
          }
        }
        // must be HTTP
        guard let http = resp as? HTTPURLResponse else {
          print("⚠️ [NetworkManager] loginJSON non-HTTP response:", resp ?? "nil")
          return DispatchQueue.main.async {
            completion(.failure(.invalidResponse))
          }
        }
        // non-2xx? log status + body
        guard (200..<300).contains(http.statusCode) else {
          let bodyText = data.flatMap { String(data: $0, encoding: .utf8) } ?? "<no body>"
          print("⚠️ [NetworkManager] loginJSON HTTP \(http.statusCode) →", bodyText)
          return DispatchQueue.main.async {
            completion(.failure(.serverError("HTTP \(http.statusCode)")))
          }
        }
        // data must exist
        guard let d = data else {
          print("⚠️ [NetworkManager] loginJSON HTTP \(http.statusCode) but no data")
          return DispatchQueue.main.async {
            completion(.failure(.invalidResponse))
          }
        }
        // decode
        do {
          let dec = try JSONDecoder().decode(LoginResponse.self, from: d)
          print("✅ [NetworkManager] loginJSON succeeded, token:", dec.token)
          DatabaseManager.shared.saveJwtApiToken(dec.token)
          DatabaseManager.shared.saveRefreshToken(dec.refreshToken)
          DatabaseManager.shared.saveUser(dec.user)
          DispatchQueue.main.async {
            completion(.success((token: dec.token, user: dec.user)))
          }
        } catch {
          print("⚠️ [NetworkManager] loginJSON decode error:", error)
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
        return URLSession(configuration: cfg,
                          delegate: InsecureTrustDelegate(),
                          delegateQueue: nil)
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

    /// Your front-end root
    private let baseURL = URL(string: "https://test.nemausa.org")!

    // MARK: – Helpers

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
                    print("✅ fetched CSRF token:", token)
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
                let profile = UserProfile(
                    id:                   0,
                    name:                 name,
                    dateOfBirth:          dob,
                    address:              address,
                    email:                email,
                    phone:                phone,
                    comments:             nil,
                    membershipExpiryDate: nil
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
                    "name": name,
                    "phone": phone,
                    "address": address,
                    "user_id": String(userId)
                ]
                let bodyString = params
                    .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)" }
                    .joined(separator: "&")
                req.httpBody = bodyString.data(using: .utf8)

                self.session.dataTask(with: req) { data, resp, err in
                    if let err = err {
                        return DispatchQueue.main.async {
                            completion(.failure(.serverError(err.localizedDescription)))
                        }
                    }
                    guard let http = resp as? HTTPURLResponse,
                          (200..<400).contains(http.statusCode),
                          let htmlData = data,
                          let html     = String(data: htmlData, encoding: .utf8)
                    else {
                        return DispatchQueue.main.async {
                            completion(.failure(.invalidResponse))
                        }
                    }

                    // on success we re-scrape the profile page to return the updated UserProfile
                    do {
                        let doc   = try SwiftSoup.parse(html)
                        let name  = try doc.select("input[name=name]").first()?.attr("value") ?? ""
                        let email = try doc.select("input[name=email]").first()?.attr("value") ?? ""
                        let phone = try doc.select("input[name=phone]").first()?.attr("value") ?? ""
                        let dob   = try doc.select("input[name=dateOfBirth]").first()?.attr("value") ?? ""
                        let addr  = try doc.select("textarea[name=address]").first()?.text()    ?? ""

                        let updated = UserProfile(
                            id:                   userId,
                            name:                 name,
                            dateOfBirth:          dob,
                            address:              addr,
                            email:                email,
                            phone:                phone,
                            comments:             nil,
                            membershipExpiryDate: nil
                        )
                        DispatchQueue.main.async { completion(.success(updated)) }
                    } catch {
                        DispatchQueue.main.async {
                            completion(.failure(.decodingError(error)))
                        }
                    }
                }
                .resume()
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
          self.refreshToken { result in
            switch result {
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
                let decoded = try JSONDecoder().decode(RefreshResponse.self, from: bytes)
                DatabaseManager.shared.saveJwtApiToken(decoded.token)
                DatabaseManager.shared.saveRefreshToken(decoded.refreshToken)
                DispatchQueue.main.async { completion(.success(decoded.token)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(.decodingError(error))) }
            }
        }
        .resume()
    }

    /// JSON POST `/register`
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
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any?] = [
            "name":            name,
            "phone":           phone,
            "email":           email,
            "confirmEmail":    confirmEmail,
            "password":        password,
            "confirmPassword": confirmPassword,
            "dateOfBirth":     dateOfBirth,
            "address":         address,
            "spouseName":      spouseName,
            "spouseEmail":     spouseEmail,
            "spouseDob":       spouseDob,
            "joinAsMember":    joinAsMember,
            "captchaToken":    captchaToken
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

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
                let decoded = try JSONDecoder().decode(LoginResponse.self, from: bytes)
                DatabaseManager.shared.saveJwtApiToken(decoded.token)
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
}

// MARK: – Trust & Redirects for loginSession
extension NetworkManager: URLSessionDelegate, URLSessionTaskDelegate {
    // Trust the test cert
    func urlSession(_ session: URLSession,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void)
    {
        let host = challenge.protectionSpace.host
        if host == "test.nemausa.org",
           let trust = challenge.protectionSpace.serverTrust
        {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }

    // Prevent redirects on loginSession so we can see the 302
    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void)
    {
        if session == loginSession {
            completionHandler(nil)
        } else {
            completionHandler(request)
        }
    }
}
