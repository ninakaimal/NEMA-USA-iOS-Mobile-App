//
//  PaymentManager.swift
//  NEMA USA
//
////  Created by Sajith on 5/5/25.

import Foundation

enum PaymentError: Error {
  case serverError(String)
  case invalidResponse
  case parseError(String)
}

private struct CreateOrderResponse: Decodable {
  let orderID: String
  let approveUrl: String
}

final class PaymentManager: NSObject {
  static let shared = PaymentManager()
  private override init() {}

  /// point at your JSON-API server
  private let baseURL = URL(string: "https://nema-api.kanakaagro.in")!

  private lazy var session: URLSession = {
    let cfg = URLSessionConfiguration.default
    return URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
  }()

  /// 1) Create a PayPal order and return the approve URL
  func createOrder(
    amount: String,
    currency: String = "USD",
    completion: @escaping (Result<URL, PaymentError>) -> Void
  ) {
    let url = baseURL.appendingPathComponent("api/create-paypal-order")
    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.addValue("application/json", forHTTPHeaderField: "Content-Type")

    // **include your JWT**
    if let jwt = DatabaseManager.shared.jwtApiToken {
      print("🔑 [PaymentManager] createOrder sending JWT: \(jwt)")
      req.addValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
    } else {
      print("⚠️ [PaymentManager] createOrder NO JWT found!")
    }

    req.httpBody = try? JSONSerialization.data(
      withJSONObject: ["amount": amount, "currency": currency],
      options: []
    )

    session.dataTask(with: req) { data, resp, err in
      if let e = err {
        return DispatchQueue.main.async {
          completion(.failure(.serverError(e.localizedDescription)))
        }
      }
      // must be HTTP
      guard let http = resp as? HTTPURLResponse else {
        print("⚠️ [PaymentManager] createOrder non-HTTP response:", resp ?? "nil")
        return DispatchQueue.main.async {
          completion(.failure(.invalidResponse))
        }
      }
      // non-2xx? log status + body
      guard (200..<300).contains(http.statusCode) else {
        let bodyText = data.flatMap { String(data: $0, encoding: .utf8) } ?? "<no body>"
        print("⚠️ [PaymentManager] createOrder HTTP \(http.statusCode) →", bodyText)
        return DispatchQueue.main.async {
          completion(.failure(.invalidResponse))
        }
      }
      // data must exist
      guard let d = data else {
        print("⚠️ [PaymentManager] createOrder HTTP \(http.statusCode) but no data")
        return DispatchQueue.main.async {
          completion(.failure(.invalidResponse))
        }
      }

      // decode
      do {
        let decoded = try JSONDecoder().decode(CreateOrderResponse.self, from: d)
        guard let approval = URL(string: decoded.approveUrl) else {
          return DispatchQueue.main.async {
            completion(.failure(.parseError("Invalid approveUrl")))
          }
        }
        print("✅ [PaymentManager] createOrder got approval URL:", approval)
        DispatchQueue.main.async {
          completion(.success(approval))
        }
      } catch {
        print("⚠️ [PaymentManager] createOrder parse error:", error)
        DispatchQueue.main.async {
          completion(.failure(.parseError(error.localizedDescription)))
        }
      }
    }
    .resume()
  }

  /// 2) Capture the order once PayPal redirects you back
  func captureOrder(
    orderID:   String,
    amount:    String,
    approveUrl: String,
    completion: @escaping (Result<Void, PaymentError>) -> Void
  ) {
    let url = baseURL.appendingPathComponent("api/capture-paypal-order")
    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.addValue("application/json", forHTTPHeaderField: "Content-Type")

    // **include your JWT**
    if let jwt = DatabaseManager.shared.jwtApiToken {
      print("🔑 [PaymentManager] captureOrder sending JWT: \(jwt)")
      req.addValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
    } else {
      print("⚠️ [PaymentManager] captureOrder NO JWT found!")
    }

    req.httpBody = try? JSONSerialization.data(
      withJSONObject: [
        "orderID":    orderID,
        "amount":     amount,
        "approveUrl": approveUrl
      ],
      options: []
    )

    session.dataTask(with: req) { data, resp, err in
      if let e = err {
        return DispatchQueue.main.async {
          completion(.failure(.serverError(e.localizedDescription)))
        }
      }
      // must be HTTP
      guard let http = resp as? HTTPURLResponse else {
        print("⚠️ [PaymentManager] captureOrder non-HTTP response:", resp ?? "nil")
        return DispatchQueue.main.async {
          completion(.failure(.invalidResponse))
        }
      }
      // non-2xx? log JSON
      guard (200..<300).contains(http.statusCode) else {
        if let d = data,
           let json = try? JSONSerialization.jsonObject(with: d, options: .allowFragments) {
          print("⚠️ [PaymentManager] captureOrder HTTP \(http.statusCode):", json)
        } else {
          print("⚠️ [PaymentManager] captureOrder HTTP \(http.statusCode), no JSON body")
        }
        return DispatchQueue.main.async {
          completion(.failure(.invalidResponse))
        }
      }
      print("✅ [PaymentManager] captureOrder succeeded")
      DispatchQueue.main.async {
        completion(.success(()))
      }
    }
    .resume()
  }
}

extension PaymentManager: URLSessionDelegate, URLSessionTaskDelegate {
  func urlSession(_ session: URLSession,
                  didReceive challenge: URLAuthenticationChallenge,
                  completionHandler: @escaping (URLSession.AuthChallengeDisposition,
                                                URLCredential?) -> Void)
  {
    completionHandler(.performDefaultHandling, nil)
  }
  func urlSession(_ session: URLSession,
                  task: URLSessionTask,
                  willPerformHTTPRedirection response: HTTPURLResponse,
                  newRequest request: URLRequest,
                  completionHandler: @escaping (URLRequest?) -> Void)
  {
    completionHandler(request)
  }
}
