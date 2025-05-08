//
//  PayPalCallbackHandler.swift
//  NEMA USA
//
//  Created by Sajith on 5/8/25.
//

import Foundation
import UIKit

class PayPalCallbackHandler {

    func canHandle(url: URL) -> Bool {
        return url.host == "test.nemausa.org" && url.path.contains("payment_status")
    }

    func handle(url: URL) {
        NotificationCenter.default.post(name: .paypalCallback, object: url)
    }

    func registerCallbackObserver() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(receivePayPalCallback(_:)),
                                               name: .paypalCallback,
                                               object: nil)
    }
    
    @objc private func receivePayPalCallback(_ notification: Notification) {
        guard let url = notification.object as? URL else { return }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        guard let paymentId = components?.queryItems?.first(where: { $0.name == "paymentId" })?.value,
              let payerId = components?.queryItems?.first(where: { $0.name == "PayerID" })?.value else {
            print("Invalid PayPal callback URL")
            return
        }

        PaymentManager.shared.captureOrder(paymentId: paymentId, payerId: payerId) { result in
            switch result {
            case .success:
                print("✅ Payment captured successfully")
                NotificationCenter.default.post(name: .paypalCaptureSuccess, object: nil)
            case .failure(let error):
                print("❌ Payment capture failed: \(error)")
                NotificationCenter.default.post(name: .paypalCaptureFailure, object: error)
            }
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

extension Notification.Name {
    static let paypalCallback = Notification.Name("paypalCallback")
    static let paypalCaptureSuccess = Notification.Name("paypalCaptureSuccess")
    static let paypalCaptureFailure = Notification.Name("paypalCaptureFailure")
}
