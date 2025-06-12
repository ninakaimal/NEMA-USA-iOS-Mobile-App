//
//  PayPalView.swift
//  NEMA USA
//
//  Created by Sajith on 5/7/25.
//

import SwiftUI
@preconcurrency import WebKit

struct PayPalView: UIViewRepresentable {
    let approvalURL: URL
    @Binding var showPaymentError: Bool
    @Binding var paymentErrorMessage: String
    @Binding var showPurchaseSuccess: Bool
    @Binding var paymentConfirmationData: PaymentConfirmationResponse? // supports membership date updates upon successful payment
    let comments: String
    let successMessage: String


    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        let webView = WKWebView(frame: .zero, configuration: cfg)
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: approvalURL))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        // no-op
    }

    class Coordinator: NSObject, WKNavigationDelegate, URLSessionDelegate {
        let parent: PayPalView

        private lazy var urlSession: URLSession = {
            let config = URLSessionConfiguration.default
            config.httpCookieStorage = HTTPCookieStorage.shared
            config.httpCookieAcceptPolicy = .always
            config.httpShouldSetCookies = true
            return URLSession(configuration: config, delegate: self, delegateQueue: nil)
        }()

        init(_ parent: PayPalView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {

            guard let url = navigationAction.request.url else {
                print("🔍 Navigation action URL is nil")
                decisionHandler(.allow)
                return
            }
            print("🔍 WebView navigating to URL:", url.absoluteString)
            
            if url.host?.contains("nemausa.org") == true,
               let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let paymentId = comps.queryItems?.first(where: { $0.name == "paymentId" })?.value,
               let payerId = comps.queryItems?.first(where: { $0.name == "PayerID" })?.value {

                print("✅ Detected PayPal payment callback. PaymentId: \(paymentId), PayerID: \(payerId)")
                
                // 🔥 Pass the dynamically navigated URL here!
                confirmPaymentOnBackend(
                    paymentId: paymentId,
                    payerId: payerId,
                    callbackURL: url, // Pass actual callback URL
                    comments: parent.comments
                )
                
                decisionHandler(.cancel)
                return
            }

            decisionHandler(.allow)
        }

        // 🔥 ADD THIS METHOD BELOW:
            func webView(_ webView: WKWebView,
                         didReceive challenge: URLAuthenticationChallenge,
                         completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {

                if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
                   challenge.protectionSpace.host.contains("nemausa.org"),
                   let serverTrust = challenge.protectionSpace.serverTrust {
                    print("⚠️ Bypassing SSL for domain:", challenge.protectionSpace.host)
                    completionHandler(.useCredential, URLCredential(trust: serverTrust))
                } else {
                    completionHandler(.performDefaultHandling, nil)
                }
            }
 
        private func confirmPaymentOnBackend(paymentId: String, payerId: String, callbackURL: URL, comments: String) {
            guard let comps = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false) else {
                parent.paymentErrorMessage = "Invalid callback URL"
                parent.showPaymentError = true
                return
            }

            // Dynamically map all query items from callbackURL
            var queryItemsDict = Dictionary(uniqueKeysWithValues: comps.queryItems?.map { ($0.name, $0.value ?? "") } ?? [])
            
            if let idValue = queryItemsDict["id"] {
                print("🔍 Dynamically included 'id':", idValue)
            } else {
                print("⚠️ 'id' parameter not included in queryItemsDict")
            }

            // Explicitly set essential payment params
            queryItemsDict["paymentId"] = paymentId
            queryItemsDict["PayerID"] = payerId
            queryItemsDict["name"] = UserDefaults.standard.string(forKey: "memberName") ?? ""
            queryItemsDict["email"] = UserDefaults.standard.string(forKey: "emailAddress") ?? ""
            queryItemsDict["phone"] = UserDefaults.standard.string(forKey: "phoneNumber") ?? ""
            queryItemsDict["comments"] = comments
            if queryItemsDict["item"] == nil || queryItemsDict["item"]!.isEmpty {
                 queryItemsDict["item"] = comments
            }

            // Build final URL for v1/payment_status_mobile
            var components = URLComponents(string: "https://nemausa.org/v1/payment_status_mobile")!
            // Important: Ensure queryItems from callbackURL are preserved and PayerID/paymentId are added/overridden
            components.queryItems = queryItemsDict.map { URLQueryItem(name: $0.key, value: $0.value) }

            guard let url = components.url else {
                parent.paymentErrorMessage = "Invalid URL for backend capture call"
                parent.showPaymentError = true
                return
            }


            var request = URLRequest(url: url)
             request.httpMethod = "GET" // As per your backend route for payment_status_mobile
             request.addValue("application/json", forHTTPHeaderField: "Accept")
             
             // Add JWT token if your v1/payment_status_mobile endpoint is protected
             // and needs to identify the user for certain operations (though often it's public
             // and relies on signed parameters or session from PayPal callback).
             // if let jwtToken = DatabaseManager.shared.jwtApiToken {
             //     request.setValue("Bearer \(jwtToken)", forHTTPHeaderField: "Authorization")
             // }
             
             print("🔍 [PayPalView.confirmPayment] Initiating backend confirmation. URL: \(url.absoluteString)")
             // Log the full queryItemsDict being sent
             // print("🔍 [PayPalView.confirmPayment] Query Parameters Sent: \(queryItemsDict)")


             urlSession.dataTask(with: request) { data, response, error in
                 guard error == nil, let httpResponse = response as? HTTPURLResponse, let responseData = data else {
                     DispatchQueue.main.async {
                         let nsError = error as NSError?
                         print("❌ [PayPalView.confirmPayment] Backend call network/transport error: \(error?.localizedDescription ?? "Unknown error"). Code: \(nsError?.code ?? 0)")
                         self.parent.paymentErrorMessage = error?.localizedDescription ?? "Network error during payment confirmation."
                         self.parent.showPaymentError = true
                     }
                     return
                 }

                 // Log raw response for debugging
                 // if let responseString = String(data: responseData, encoding: .utf8) {
                 //    print("📦 [PayPalView.confirmPayment] Backend Raw Response (\(httpResponse.statusCode)): \(responseString)")
                 // }
                 
                 if (200...299).contains(httpResponse.statusCode) {
                     do {
                         // Use a JSONDecoder. If you have a global one with specific strategies (e.g., snake_case), use that.
                         let decoder = JSONDecoder()
                         // Ensure your PaymentConfirmationResponse struct matches the JSON keys from the backend
                         // For example, if backend sends "online_payment_id", struct should have "online_payment_id" or use keyDecodingStrategy
                         let confirmationResponse = try decoder.decode(PaymentConfirmationResponse.self, from: responseData)
                         
                         DispatchQueue.main.async {
                             print("✅ [PayPalView.confirmPayment] Payment captured successfully (HTTP \(httpResponse.statusCode)). Parsed: \(confirmationResponse)")
                             self.parent.paymentConfirmationData = confirmationResponse // Update the binding
                             self.parent.showPurchaseSuccess = true
                         }
                     } catch {
                         DispatchQueue.main.async {
                             print("❌ [PayPalView.confirmPayment] Failed to decode PaymentConfirmationResponse: \(error)")
                              if let responseString = String(data: responseData, encoding: .utf8) {
                                 print("📦 [PayPalView.confirmPayment] Failing JSON to decode: \(responseString)")
                             }
                             self.parent.paymentErrorMessage = "Payment confirmed, but response processing failed: \(error.localizedDescription)"
                             self.parent.showPaymentError = true // Show error, but payment might be okay on backend.
                         }
                     }
                 } else if (300...399).contains(httpResponse.statusCode),
                           let redirectLocation = httpResponse.allHeaderFields["Location"] as? String,
                           let redirectURL = URL(string: redirectLocation) {
                     // This case might not be typical for a GET API endpoint like payment_status_mobile
                     // unless it's designed to redirect under certain conditions.
                     print("🔍 [PayPalView.confirmPayment] Backend responded with redirect (\(httpResponse.statusCode)) to: \(redirectURL.absoluteString)")
                     self.followRedirect(redirectURL)
                 
                 } else {
                     DispatchQueue.main.async {
                         var errorMessage = "Payment confirmation failed with HTTP Error \(httpResponse.statusCode)."
                         if let responseString = String(data: responseData, encoding: .utf8) {
                             // Try to parse a generic error message from backend if available
                             // This depends on your backend's error response structure
                             // For example, if it returns { "error": "message" }
                             // You could try:
                             // if let jsonError = try? JSONDecoder().decode([String: String].self, from: responseData),
                             //    let specificError = jsonError["error"] {
                             //     errorMessage += " Server message: \(specificError)"
                             // } else {
                             //     errorMessage += " Response: \(responseString)"
                             // }
                              print("❌ [PayPalView.confirmPayment] Backend returned HTTP \(httpResponse.statusCode). Body: \(responseString)")
                              errorMessage += " Please check details or contact support."
                         }
                         self.parent.paymentErrorMessage = errorMessage
                         self.parent.showPaymentError = true
                     }
                 }
             }.resume()
         }

        private func followRedirect(_ url: URL) {
            print("🔍 [PayPalView.followRedirect] Initiating redirect request to: \(url.absoluteString)")
            var redirectRequest = URLRequest(url: url)
            redirectRequest.httpMethod = "GET" // Assuming redirect target is GET
            redirectRequest.addValue("application/json", forHTTPHeaderField: "Accept")
            // Add JWT token if redirect target requires authentication

            urlSession.dataTask(with: redirectRequest) { data, response, error in
                guard error == nil, let httpResponse = response as? HTTPURLResponse, let responseData = data else {
                    DispatchQueue.main.async {
                        print("❌ [PayPalView.followRedirect] Redirect request failed: \(error?.localizedDescription ?? "Unknown error")")
                        self.parent.paymentErrorMessage = error?.localizedDescription ?? "Error following payment redirect."
                        self.parent.showPaymentError = true
                    }
                    return
                }
                
                // Log raw response for debugging
                // if let responseString = String(data: responseData, encoding: .utf8) {
                //    print("📦 [PayPalView.followRedirect] Backend Raw Response (\(httpResponse.statusCode)): \(responseString)")
                // }

                if (200...299).contains(httpResponse.statusCode) {
                    do {
                        let decoder = JSONDecoder()
                        let confirmationResponse = try decoder.decode(PaymentConfirmationResponse.self, from: responseData)
                        DispatchQueue.main.async {
                            print("✅ [PayPalView.followRedirect] Redirect successfully followed. Parsed Response: \(confirmationResponse)")
                            self.parent.paymentConfirmationData = confirmationResponse // Update the binding
                            self.parent.showPurchaseSuccess = true
                        }
                    } catch {
                         DispatchQueue.main.async {
                            print("❌ [PayPalView.followRedirect] Failed to decode PaymentConfirmationResponse after redirect: \(error)")
                            if let responseString = String(data: responseData, encoding: .utf8) {
                                print("📦 [PayPalView.followRedirect] Failing JSON to decode: \(responseString)")
                            }
                            self.parent.paymentErrorMessage = "Payment redirect successful, but response processing failed: \(error.localizedDescription)"
                            self.parent.showPaymentError = true
                        }
                    }
                } else {
                    DispatchQueue.main.async {
                        var errorMessage = "Payment redirect failed with HTTP Error \(httpResponse.statusCode)."
                         if let responseString = String(data: responseData, encoding: .utf8) {
                             print("❌ [PayPalView.followRedirect] Redirect returned HTTP \(httpResponse.statusCode). Body: \(responseString)")
                             errorMessage += " Please contact support."
                        }
                        self.parent.paymentErrorMessage = errorMessage
                        self.parent.showPaymentError = true
                    }
                }
            }.resume()
        }

        // Allow self-signed certificates temporarily for testing
        func urlSession(_ session: URLSession,
                        didReceive challenge: URLAuthenticationChallenge,
                        completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {

            guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
                  challenge.protectionSpace.host == "nemausa.org",
                  let trust = challenge.protectionSpace.serverTrust else {
                completionHandler(.performDefaultHandling, nil)
                return
            }

            // ⚠️ For TESTING ONLY: Accept invalid SSL certificate
            completionHandler(.useCredential, URLCredential(trust: trust))
        }
    }
}
