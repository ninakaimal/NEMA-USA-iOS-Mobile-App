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
            
            if url.host?.contains("test.nemausa.org") == true,
               let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let paymentId = comps.queryItems?.first(where: { $0.name == "paymentId" })?.value,
               let payerId = comps.queryItems?.first(where: { $0.name == "PayerID" })?.value {

                print("✅ Detected PayPal payment callback. PaymentId: \(paymentId), PayerID: \(payerId)")
                
                // 🔥 Pass the dynamically navigated URL here!
                confirmPaymentOnBackend(
                    paymentId: paymentId,
                    payerId: payerId,
                    callbackURL: url, // ✅ Critical fix: Pass actual callback URL
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
                   challenge.protectionSpace.host.contains("test.nemausa.org"),
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
            queryItemsDict["item"] = comments

            // Build final URL
              var components = URLComponents(string: "https://test.nemausa.org/v1/payment_status_mobile")!
              components.queryItems = queryItemsDict.map { URLQueryItem(name: $0.key, value: $0.value) }

              guard let url = components.url else {
                  parent.paymentErrorMessage = "Invalid URL for backend capture call"
                  parent.showPaymentError = true
                  return
              }

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.addValue("application/json", forHTTPHeaderField: "Accept")
            
            print("🔍 Initiating backend confirmation at URL:", url.absoluteString)

                urlSession.dataTask(with: request) { data, response, error in
                    guard error == nil, let httpResponse = response as? HTTPURLResponse else {
                        DispatchQueue.main.async {
                        print("❌ Backend call failed: \(error!.localizedDescription)")
                            self.parent.paymentErrorMessage = error?.localizedDescription ?? "Unknown error"
                            self.parent.showPaymentError = true
                        }
                        return
                    }

                print("🔍 Backend response status code:", httpResponse.statusCode)
                
                    if (300...399).contains(httpResponse.statusCode),
                       let redirectLocation = httpResponse.allHeaderFields["Location"] as? String,
                       let redirectURL = URL(string: redirectLocation) {

                    // ✅ Follow redirect explicitly
                        print("🔍 Following redirect to:", redirectURL.absoluteString)
                        self.followRedirect(redirectURL)
                    
                    } else if (200...299).contains(httpResponse.statusCode) {
                        DispatchQueue.main.async {
                            print("✅ Payment captured successfully (HTTP 200)")
                            self.parent.showPurchaseSuccess = true
                        }
                    } else {
                        DispatchQueue.main.async {
                            print("❌ Backend returned HTTP \(httpResponse.statusCode)")
                            self.parent.paymentErrorMessage = "HTTP Error \(httpResponse.statusCode)"
                            self.parent.showPaymentError = true
                        }
                    }
                }.resume()
            }

        private func followRedirect(_ url: URL) {
            print("🔍 Initiating redirect request to:", url.absoluteString)
            var redirectRequest = URLRequest(url: url)
            redirectRequest.httpMethod = "GET"

            urlSession.dataTask(with: redirectRequest) { data, response, error in
                guard error == nil, let httpResponse = response as? HTTPURLResponse else {
                    DispatchQueue.main.async {
                        print("❌ Redirect request failed: \(error!.localizedDescription)")
                        self.parent.paymentErrorMessage = error!.localizedDescription
                        self.parent.showPaymentError = true
                    }
                    return
                }

                if (200...299).contains(httpResponse.statusCode) {
                    DispatchQueue.main.async {
                        print("✅ Redirect successfully followed and payment captured.")
                        self.parent.showPurchaseSuccess = true
                    }
                } else {
                    DispatchQueue.main.async {
                        print("❌ Redirect returned HTTP \(httpResponse.statusCode)")
                        self.parent.paymentErrorMessage = "Redirect HTTP Error \(httpResponse.statusCode)"
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
                  challenge.protectionSpace.host == "test.nemausa.org",
                  let trust = challenge.protectionSpace.serverTrust else {
                completionHandler(.performDefaultHandling, nil)
                return
            }

            // ⚠️ For TESTING ONLY: Accept invalid SSL certificate
            completionHandler(.useCredential, URLCredential(trust: trust))
        }
    }
}
