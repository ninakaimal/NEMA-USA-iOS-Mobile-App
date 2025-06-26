//
//  PaymentManager.swift
//  NEMA USA
//
//  Created by Sajith on 5/5/25.
//  Updated with correct PayPal route integration
// //  Updated by Sajith on 5/22/25 to add panthiId

import Foundation

struct PaymentConfirmationResponse: Codable {
    let status: String
    let payment_id: String? // PayPal's paymentId
    let transaction_id: String? // PayPal's saleId or transactionId
    let online_payment_db_id: Int? // <<<< ADD: Your DB's OnlinePayment PK (e.g., 3490)
    let package_id_for_renewal: Int? // <<<< ADD: The package_id for the renewal
    let message: String?             // General message from backend
    let membership_expiry: String?
    let ticket_pdf_url: String?
}

enum PaymentError: Error { /* ... as before ... */
    case serverError(String)
    case invalidResponse
    case parseError(String)
}

final class PaymentManager: NSObject {
    static let shared = PaymentManager()
    private override init() {}
    
    private var createOrderCallback: ((Result<URL, PaymentError>) -> Void)?
    private var payPalPaymentIdForCapture: String?
    private var appSpecificTicketPurchaseId: Int? // Your DB's ticket_purchase.id if returned by createOrder

    
    private let baseURL = URL(string: "https://nemausa.org")!
    
    private lazy var session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.httpCookieAcceptPolicy = .always // Needed if /v1/pay_with_paypal_mobile is under 'web' middleware
        cfg.httpCookieStorage = HTTPCookieStorage.shared
        // Ensure InsecureTrustDelegate is correctly defined as you have it
        return URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
    }()
    
    // Helper function for initial cookie fetch
    func fetchInitialCookies(completion: @escaping (Bool) -> Void) {
        var components = URLComponents(url: baseURL.appendingPathComponent("buy_ticket"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "event_id", value: "160")]
        
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
        initialRequest.setValue("nemausa.org", forHTTPHeaderField: "Host")
        initialRequest.setValue("https://nemausa.org", forHTTPHeaderField: "Referer")
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
        eventID: Int? = nil,
        email: String?,
        name: String?,
        phone: String?,
        membershipType: String? = nil,  // explicitly set as "membership" or "renew" when applicable
        packageId: Int? = nil,
        packageYears: Int? = nil,
        userId: Int? = nil,
        panthiId: Int? = nil,
        lineItems: [[String: Any]]? = nil,
        completion: @escaping (Result<URL, PaymentError>) -> Void
    ){
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
            
            // Add JWT token if available (for user identification on backend)
            if let jwtToken = DatabaseManager.shared.jwtApiToken { // <<<< UNCOMMENT THIS BLOCK
                req.addValue("Bearer \(jwtToken)", forHTTPHeaderField: "Authorization")
                print("✅ [PaymentManager] JWT token added to createOrder request.")
            } else {
                print("ℹ️ [PaymentManager] No JWT token found, guest purchase assumed for createOrder.")
            }

            if let cookie = HTTPCookieStorage.shared.cookies?.first(where: { $0.name == "XSRF-TOKEN" }),
               let token = cookie.value.removingPercentEncoding {
                req.addValue(token, forHTTPHeaderField: "X-XSRF-TOKEN")
            }

            // Explicit logic to determine the correct 'type'
            var paymentTypeDetermined: String
            if let explicitMembershipType = membershipType, ["membership", "new_member", "renew"].contains(explicitMembershipType.lowercased()) {
                paymentTypeDetermined = explicitMembershipType.lowercased()
            } else if eventID != nil {
                paymentTypeDetermined = "ticket"
            } else {
                // Fallback or error if type cannot be determined
                print("⚠️ Could not determine payment type for createOrder. EventID is nil and no explicit membership type.")
                DispatchQueue.main.async {
                    completion(.failure(.serverError("Could not determine payment type.")))
                }
                return
            }
            
            print("[PaymentManager] createOrder: Payment type set to: \(paymentTypeDetermined)")

            
            var payload: [String: Any] = [
                "amount": amount,
                "item": "\(eventTitle) Purchase", // General item name
                "description": "\(eventTitle) - \(name ?? "Guest")", // More specific description
                "returnUrl": "https://nemausa.org/payment_status", // This is PayPal's, backend handles mobile redirect
                "type": paymentTypeDetermined,
                "name": name ?? "",
                "email": email ?? "",
                "phone": phone ?? ""
            ]

            // Add parameters based on payment type
            switch paymentTypeDetermined {
            case "ticket":
                if let eventID = eventID {
                    payload["event_id"] = eventID
                }
                if let panthiId = panthiId {
                    payload["panthi_id"] = panthiId
                }
                // ** Add line_items if it's a ticket purchase and lineItems are provided **
                if let lineItems = lineItems, !lineItems.isEmpty {
                    payload["line_items"] = lineItems // This should be an array of dictionaries
 //                   print("✅ [PaymentManager] Including line_items in payload for ticket: \(lineItems)")
                } else {
                    print("⚠️ [PaymentManager] line_items not provided or empty for ticket purchase type.")
                }

            case "membership", "new_member":
                guard let packageId = packageId, let packageYears = packageYears, let userIdForNewMembership = userId else {
                    print("⚠️ Missing packageId, packageYears, or userId for new membership")
                    DispatchQueue.main.async {
                        completion(.failure(.serverError("Missing new membership details (package, years, or user ID).")))
                    }
                    return
                }
                payload["pckg_id"] = packageId
                payload["no"] = packageYears
                payload["id"] = userIdForNewMembership // Backend expects 'id' for user_id

            case "renew":
                guard let packageId = packageId, let packageYears = packageYears, let userIdForRenewal = userId else {
                    print("⚠️ Missing packageId, packageYears, or userId for membership renewal")
                    DispatchQueue.main.async {
                        completion(.failure(.serverError("Missing renewal details (package, years, or user ID).")))
                    }
                    return
                }
                payload["pckg_id"] = packageId
                payload["no"] = packageYears
                payload["id"] = userIdForRenewal // Backend expects 'id' for user_id (or membership_id depending on backend)
                                                // Your web flow seems to use membership_id for 'id' in session for renew,
                                                // but user_id for 'new_member'. Clarify if backend expects user_id or membership.id here.
                                                // For now, assuming 'id' passed to createOrder is the user_id to align with 'new_member'.
            default:
                print("⚠️ Unknown payment type for payload modification: \(paymentTypeDetermined)")
            }
            
            print("[PaymentManager] createOrder: Sending payload to backend: \(payload)")
            req.httpBody = try? JSONSerialization.data(withJSONObject: payload, options: .prettyPrinted) // .prettyPrinted for easier debugging

            self.createOrderCallback = completion // Store the completion handler

            self.session.dataTask(with: req) { data, resp, err in
                // ... (your existing network error handling, status code checking, and JSON parsing) ...
                // Ensure you store appSpecificTicketPurchaseId if backend returns it
                // Example from your existing code, ensure it's adapted:
                if let json = try? JSONSerialization.jsonObject(with: data!) as? [String: Any] {
                    if let ticketId = json["ticketPurchaseId"] as? Int {
                        self.appSpecificTicketPurchaseId = ticketId
                        UserDefaults.standard.set(ticketId, forKey: "ticketPurchaseId_from_createOrder") // Save it for captureOrder
                        print("✅ [PaymentManager] Stored appSpecificTicketPurchaseId: \(ticketId)")
                    }
                    if let approvalURLString = json["approval_url"] as? String,
                       let paymentId = json["payment_id"] as? String, // PayPal's Payment ID
                       let approvalURL = URL(string: approvalURLString) {
                        self.payPalPaymentIdForCapture = paymentId // Store PayPal's payment ID
                        DispatchQueue.main.async {
                            completion(.success(approvalURL))
                        }
                        return // Success path
                    }
                }
                // Fallthrough for errors
                DispatchQueue.main.async {
                     let responseBody = data.flatMap { String(data: $0, encoding: .utf8) } ?? "<no data>"
                     print("❌ [PaymentManager] createOrder failed to parse approval_url or payment_id. Body: \(responseBody)")
                     completion(.failure(.parseError("Missing approval_url or payment_id in response. Body: \(responseBody)")))
                }
            }.resume()
        }
    }
    
    // MARK: — 2) Capture the order (Updated with correct endpoint and method)
        func captureOrder(
            payerId: String,
            paymentId: String,
            memberName: String = "",
            email: String = "",
            phone: String = "",
            comments: String = "Mobile app purchase",
            type: String?,
            id: Int?,
            eventId: Int?,
            panthiId: Int? = nil,
            completion: @escaping (Result<PaymentConfirmationResponse, PaymentError>) -> Void
        ) {
            guard let paymentId = payPalPaymentIdForCapture else {
                completion(.failure(.serverError("No paymentId found")))
                return
            }
            
            var queryItems: [URLQueryItem] = [
                URLQueryItem(name: "paymentId", value: paymentId),
                URLQueryItem(name: "PayerID", value: payerId),
                URLQueryItem(name: "name", value: memberName),
                URLQueryItem(name: "email", value: email),
                URLQueryItem(name: "phone", value: phone),
                URLQueryItem(name: "comments", value: comments)
            ]
            
            // Conditionally add only if non-nil
            if let type = type {
                queryItems.append(URLQueryItem(name: "type", value: type))
            }
            if let id = id {
                queryItems.append(URLQueryItem(name: "id", value: String(id)))
            }
            if let eventId = eventId {
                queryItems.append(URLQueryItem(name: "event_id", value: String(eventId)))
            }
            
            var comps = URLComponents(
                url: baseURL.appendingPathComponent("v1/payment_status_mobile"),
                resolvingAgainstBaseURL: false
            )!

            comps.queryItems = queryItems
            
            guard let url = comps.url else {
                completion(.failure(.serverError("Bad capture URL")))
                return
            }
            // sajith - remove later
            print("captureOrder invoked with params:", payerId, memberName, email, phone, type ?? "nil", id ?? "nil", eventId ?? "nil")
            //
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
                guard let http = resp as? HTTPURLResponse, let data = data else {
                    DispatchQueue.main.async {
                        completion(.failure(.invalidResponse))
                    }
                    return
                }
                
                guard (200..<300).contains(http.statusCode) else {
                    let body = String(data: data, encoding: .utf8) ?? "<no body>"
                    print("⚠️ [PaymentManager] captureOrder HTTP \(http.statusCode)")
                    print("Headers:", http.allHeaderFields)
                    print("Body:", body)
                    DispatchQueue.main.async {
                        completion(.failure(.serverError("HTTP \(http.statusCode): \(body)")))
                    }
                    return
                }
                
                do {
                    let decoder = JSONDecoder()
                    let response = try decoder.decode(PaymentConfirmationResponse.self, from: data)
                    DispatchQueue.main.async {
                        self.payPalPaymentIdForCapture = nil // Clear paymentId on success
                        completion(.success(response))
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
extension PaymentManager: URLSessionDelegate, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.host == "nemausa.org", let trust = challenge.protectionSpace.serverTrust {
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
