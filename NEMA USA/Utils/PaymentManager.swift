//
//  PaymentManager.swift
//  NEMA USA
//
//  Created by Sajith on 5/5/25.
//  Updated with correct PayPal route integration
//

import Foundation

enum PaymentError: Error {
    case serverError(String)
    case invalidResponse
    case parseError(String)
}

final class PaymentManager: NSObject {
    static let shared = PaymentManager()
    private override init() {}

    private var createOrderCallback: ((Result<URL,PaymentError>) -> Void)?
    
    private var paymentId: String?

    private let baseURL = URL(string: "https://test.nemausa.org")!

    private lazy var session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.httpCookieAcceptPolicy = .always
        cfg.httpCookieStorage     = HTTPCookieStorage.shared
        return URLSession(configuration: cfg,
                          delegate: self,
                          delegateQueue: nil)
    }()

    // Helper function for initial cookie fetch
    func fetchInitialCookies(completion: @escaping (Bool) -> Void) {
        var components = URLComponents(url: baseURL.appendingPathComponent("buy_ticket"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "id", value: "160")]

        guard let initialURL = components.url else {
            print("❌ URL creation failed")
            completion(false)
            return
        }

        var initialRequest = URLRequest(url: initialURL)
        initialRequest.httpMethod = "GET"
        initialRequest.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        initialRequest.setValue("en-US,en;q=0.5", forHTTPHeaderField: "Accept-Language")
        initialRequest.setValue("keep-alive", forHTTPHeaderField: "Connection")
        initialRequest.setValue("test.nemausa.org", forHTTPHeaderField: "Host")
        initialRequest.setValue("https://test.nemausa.org", forHTTPHeaderField: "Referer")
        initialRequest.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")

        session.dataTask(with: initialRequest) { data, response, error in
            guard error == nil,
                  let http = response as? HTTPURLResponse,
                  (200..<400).contains(http.statusCode) else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                let responseBody = data.flatMap { String(data: $0, encoding: .utf8) } ?? "<no response>"
                print("❌ Initial cookie fetch failed. Status Code: \(statusCode), Response: \(responseBody), Error: \(error?.localizedDescription ?? "Unknown Error")")
                completion(false)
                return
            }

            print("✅ Initial cookie fetch succeeded, status code: \(http.statusCode)")
            completion(true)
        }.resume()
    }

    // MARK: — 1) Create a PayPal order
    func createOrder(
        amount: String,
        eventTitle: String,
        completion: @escaping (Result<URL, PaymentError>) -> Void
    ) {
        fetchInitialCookies { success in
            guard success else {
                DispatchQueue.main.async {
                    completion(.failure(.serverError("Failed to fetch initial cookies")))
                }
                return
            }

            let url = self.baseURL.appendingPathComponent("v1/pay_with_paypal_mobile")
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.addValue("application/json", forHTTPHeaderField: "Content-Type")
            req.addValue("application/json", forHTTPHeaderField: "Accept")

            if let cookie = HTTPCookieStorage.shared.cookies?.first(where: { $0.name == "XSRF-TOKEN" }),
               let token = cookie.value.removingPercentEncoding {
                req.addValue(token, forHTTPHeaderField: "X-XSRF-TOKEN")
            }

            let payload: [String: Any] = [
                "amount": amount,
                "item": "\(eventTitle) Tickets",
                "description": "Ticket purchase for \(eventTitle) event",
                "returnUrl": "https://test.nemausa.org/payment_status",
                "type": "ticket",
                "event_id": 160
            ]

            req.httpBody = try? JSONSerialization.data(withJSONObject: payload)

            self.session.dataTask(with: req) { data, resp, err in
                if let e = err {
                    print("❌ Network error:", e.localizedDescription)
                    DispatchQueue.main.async {
                        completion(.failure(.serverError(e.localizedDescription)))
                    }
                    return
                }

                guard let http = resp as? HTTPURLResponse else {
                    print("❌ Response was not HTTPURLResponse")
                    DispatchQueue.main.async {
                        completion(.failure(.invalidResponse))
                    }
                    return
                }

                print("🔍 HTTP Status Code:", http.statusCode)
                print("🔍 HTTP Headers:", http.allHeaderFields)
                
                guard let d = data else {
                    print("❌ Response data is nil")
                    DispatchQueue.main.async {
                        completion(.failure(.invalidResponse))
                    }
                    return
                }

                let responseBody = String(data: d, encoding: .utf8) ?? "<no body>"
                print("🔍 Response body:", responseBody)

                guard (200..<400).contains(http.statusCode) else {
                    print("❌ Status code out of range:", http.statusCode)
                    DispatchQueue.main.async {
                        completion(.failure(.invalidResponse))
                    }
                    return
                }

                do {
                    if let json = try JSONSerialization.jsonObject(with: d) as? [String: Any],
                       let approvalURLString = json["approval_url"] as? String,
                       let paymentId = json["payment_id"] as? String,
                       let approvalURL = URL(string: approvalURLString) {

                        self.paymentId = paymentId
                        print("✅ Parsed PayPal approval URL successfully:", approvalURL)
                        DispatchQueue.main.async {
                            completion(.success(approvalURL))
                        }
                    } else {
                        throw PaymentError.parseError("Missing approval_url or payment_id in JSON")
                    }
                } catch {
                    print("⚠️ JSON parse error:", error.localizedDescription)
                    DispatchQueue.main.async {
                        completion(.failure(.parseError("Failed to parse JSON: \(error.localizedDescription)")))
                    }
                }
            }.resume()
        }
    }
    
    // MARK: — 2) Capture the order (Updated with correct endpoint and method)
    func captureOrder(
        payerId: String,
        memberName: String = "",
        email: String = "",
        phone: String = "",
        comments: String = "Mobile app ticket purchase",
        completion: @escaping (Result<Void, PaymentError>) -> Void
    ) {
        guard let storedPaymentId = paymentId else {
            completion(.failure(.serverError("No paymentId found")))
            return
        }

        var comps = URLComponents(
            url: baseURL.appendingPathComponent("v1/payment_status_mobile"),
            resolvingAgainstBaseURL: false
        )!

        comps.queryItems = [
            URLQueryItem(name: "paymentId", value: storedPaymentId),
            URLQueryItem(name: "PayerID", value: payerId),
            URLQueryItem(name: "name", value: memberName),
            URLQueryItem(name: "email", value: email),
            URLQueryItem(name: "phone", value: phone),
            URLQueryItem(name: "comments", value: comments)
        ]

        guard let url = comps.url else {
            completion(.failure(.serverError("Bad capture URL")))
            return
        }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.addValue("application/json", forHTTPHeaderField: "Accept")

        session.dataTask(with: req) { data, resp, err in
            if let e = err {
                DispatchQueue.main.async {
                    completion(.failure(.serverError(e.localizedDescription)))
                }
                return
            }
            guard let http = resp as? HTTPURLResponse else {
                DispatchQueue.main.async {
                    completion(.failure(.invalidResponse))
                }
                return
            }

            if !(200..<300).contains(http.statusCode) {
                let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? "<no body>"
                print("⚠️ [PaymentManager] captureOrder HTTP \(http.statusCode)")
                print("Headers:", http.allHeaderFields)
                print("Body:", body)
                DispatchQueue.main.async {
                    completion(.failure(.serverError("HTTP \(http.statusCode): \(body)")))
                }
                return
            }

            DispatchQueue.main.async {
                self.paymentId = nil // Clear paymentId on success
                completion(.success(()))
            }
        }.resume()
    }
}

extension PaymentManager: URLSessionDelegate, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.host == "test.nemausa.org", let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        if let location = request.url, location.host?.contains("paypal.com") == true, let cb = createOrderCallback {
            DispatchQueue.main.async { cb(.success(location)) }
            createOrderCallback = nil
            task.cancel()
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}
