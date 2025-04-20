//
//  Webview.swift
//  NEMA USA
//
//  Created by Nina on 4/2/25.
//
import SwiftUI
import WebKit
import UserNotifications

struct WebView: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        return Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "scheduleNotification")
        contentController.add(context.coordinator, name: "cancelNotifications")

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = contentController

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.scrollView.bounces = false
        webView.scrollView.decelerationRate = .normal

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        let request = URLRequest(url: url)
        uiView.load(request)
    }

    // 👇 Coordinator handles JS messages
    class Coordinator: NSObject, WKScriptMessageHandler {
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "scheduleNotification", let notification = message.body as? [String: Any] {
                scheduleNotification(notification)
            } else if message.name == "cancelNotifications", let data = message.body as? [String: Any],
                      let eventId = data["eventId"] as? String {
                cancelNotifications(for: eventId)
            }
        }

        func scheduleNotification(_ data: [String: Any]) {
            guard let title = data["title"] as? String,
                  let body = data["body"] as? String,
                  let timeInterval = data["timeInterval"] as? TimeInterval else {
                print("Invalid notification data")
                return
            }

            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: timeInterval, repeats: false)
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)

            UNUserNotificationCenter.current().add(request)
        }

        func cancelNotifications(for eventId: String) {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [eventId])
        }
    }
}
