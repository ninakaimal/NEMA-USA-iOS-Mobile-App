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
                decisionHandler(.allow)
                return
            }

            if url.host?.contains("test.nemausa.org") == true,
               let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let paymentId = comps.queryItems?.first(where: { $0.name == "paymentId" })?.value,
               let payerId = comps.queryItems?.first(where: { $0.name == "PayerID" })?.value {
                // Explicitly call backend to confirm payment
                 confirmPaymentOnBackend(
                    paymentId: paymentId,
                    payerId:   payerId,
                    email:     UserDefaults.standard.string(forKey: "emailAddress") ?? "",
                    name:      UserDefaults.standard.string(forKey: "memberName") ?? "",
                    phone:     UserDefaults.standard.string(forKey: "phoneNumber") ?? "",
                    comments:  parent.comments
                )
                decisionHandler(.cancel)
                return
            }

            decisionHandler(.allow)
        }

        private func confirmPaymentOnBackend(paymentId: String, payerId: String, email: String, name: String, phone: String, comments: String) {
            var components = URLComponents(string: "https://test.nemausa.org/v1/payment_status_mobile")!
            components.queryItems = [
                URLQueryItem(name: "paymentId", value: paymentId),
                URLQueryItem(name: "PayerID", value: payerId),
                URLQueryItem(name: "name", value: name),
                URLQueryItem(name: "email", value: email),
                URLQueryItem(name: "phone", value: phone),
                URLQueryItem(name: "comments", value: comments)
            ]

            guard let url = components.url else {
                print("❌ Invalid URL for backend capture call")
                return
            }

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.addValue("text/html", forHTTPHeaderField: "Accept")

            urlSession.dataTask(with: request) { data, response, error in
                guard error == nil, let httpResponse = response as? HTTPURLResponse, let _ = data else {
                    DispatchQueue.main.async {
                        print("❌ Backend call failed: \(error!.localizedDescription)")
                        self.parent.paymentErrorMessage = error!.localizedDescription
                        self.parent.showPaymentError = true
                    }
                    return
                }

                if (300...399).contains(httpResponse.statusCode),
                   let redirectLocation = httpResponse.allHeaderFields["Location"] as? String,
                   let redirectURL = URL(string: redirectLocation) {

                    // ✅ Follow redirect explicitly
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
            var redirectRequest = URLRequest(url: url)
            redirectRequest.httpMethod = "GET"

            urlSession.dataTask(with: redirectRequest) { data, response, error in
                guard error == nil, let httpResponse = response as? HTTPURLResponse else {
                    DispatchQueue.main.async {
                        print("❌ Redirect failed: \(error!.localizedDescription)")
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
