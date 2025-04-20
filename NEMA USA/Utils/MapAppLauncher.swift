//
//  MapAppLauncher.swift
//  NEMA USA
//
//  Created by Nina on 4/16/25.


import UIKit
import SwiftUI

enum MapAppOption: String, CaseIterable {
    case apple = "Apple Maps"
    case google = "Google Maps"
    case waze = "Waze"
}

struct MapAppLauncher {
    static func presentMapOptions(for address: String) {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first,
              let rootVC = window.rootViewController else { return }

        let alert = UIAlertController(title: "Open in Maps", message: "Choose your maps app", preferredStyle: .actionSheet)
        let encodedAddress = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""

        // Apple Maps
        alert.addAction(UIAlertAction(title: MapAppOption.apple.rawValue, style: .default) { _ in
            if let url = URL(string: "http://maps.apple.com/?daddr=\(encodedAddress)") {
                UIApplication.shared.open(url)
            }
        })

        // Google Maps
        if let googleURL = URL(string: "comgooglemaps://?daddr=\(encodedAddress)&directionsmode=driving"),
           UIApplication.shared.canOpenURL(googleURL) {
            alert.addAction(UIAlertAction(title: MapAppOption.google.rawValue, style: .default) { _ in
                UIApplication.shared.open(googleURL)
            })
        } else {
            alert.addAction(UIAlertAction(title: MapAppOption.google.rawValue, style: .default) { _ in
                if let fallback = URL(string: "https://www.google.com/maps/dir/?api=1&destination=\(encodedAddress)") {
                    UIApplication.shared.open(fallback)
                }
            })
        }

        // Waze
        if let wazeURL = URL(string: "waze://?q=\(encodedAddress)"),
           UIApplication.shared.canOpenURL(wazeURL) {
            alert.addAction(UIAlertAction(title: MapAppOption.waze.rawValue, style: .default) { _ in
                UIApplication.shared.open(wazeURL)
            })
        }

        // Cancel
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        rootVC.present(alert, animated: true)
    }
}
