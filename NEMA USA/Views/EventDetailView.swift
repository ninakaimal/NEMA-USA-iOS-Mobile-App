//
//  EventDetailView.swift
//  NEMA USA
//  Created by Nina on 4/16/25.
//  Updated by Sajith on 4/22/25
//

import SwiftUI
import UIKit

struct EventDetailView: View {
    let event: Event

    init(event: Event) {
        self.event = event

        // ⚙️ Match the same orange nav‑bar styling as EventRegistrationView
        if #available(iOS 15.0, *) {
            let appearance = UINavigationBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = UIColor(Color.orange)
            appearance.titleTextAttributes = [.foregroundColor: UIColor.white]
            appearance.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
            UINavigationBar.appearance().standardAppearance   = appearance
            UINavigationBar.appearance().scrollEdgeAppearance = appearance
        } else {
            UINavigationBar.appearance().barTintColor            = .orange
            UIBarButtonItem.appearance().tintColor               = .white
        }
        UINavigationBar.appearance().tintColor = .white
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Orange status‑bar wedge
            Color.orange
                .ignoresSafeArea(edges: .top)
                .frame(height: 56)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {

                    // MARK: – Title & Category
                    Text(event.title)
                        .font(.title2).bold()
                        .foregroundColor(.primary)

                    Text(event.category)
                        .font(.subheadline).italic()
                        .foregroundColor(.secondary)

                    // MARK: – Event Image
                    let asset = event.imageUrl.replacingOccurrences(of: ".png", with: "")
                    if UIImage(named: asset) != nil {
                        Image(asset)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 200)
                            .clipped()
                            .cornerRadius(12)
                    } else {
                        Color.gray.opacity(0.3)
                            .frame(height: 200)
                            .cornerRadius(12)
                    }

                    // MARK: – Details Card
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "calendar")
                                .foregroundColor(.orange)
                            Text("Date & Time")
                                .font(.headline)
                                .foregroundColor(.primary)
                        }
                        Text(
                            event.isTBD
                                ? "To be announced"
                                : [
                                    event.date?.formatted(.dateTime.month().day().year()),
                                    event.date?.formatted(.dateTime.hour().minute().locale(Locale.current))
                                  ]
                                  .compactMap { $0 }
                                  .joined(separator: " • ")
                        )
                        .font(.subheadline)
                        .foregroundColor(.primary)

                        Divider()

                        HStack(spacing: 8) {
                            Image(systemName: "mappin.and.ellipse")
                                .foregroundColor(.orange)
                            Text("Location")
                                .font(.headline)
                                .foregroundColor(.primary)
                        }
                        Text(event.location)
                            .font(.subheadline)
                            .foregroundColor(.primary)
                            .fixedSize(horizontal: false, vertical: true)

                        Button(action: {
                            MapAppLauncher.presentMapOptions(for: event.location)
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "location.fill")
                                Text("View on Map")
                            }
                        }
                        .font(.subheadline.bold())
                        .foregroundColor(.orange)
                        .buttonStyle(PlainButtonStyle())
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)
                    .shadow(color: Color.black.opacity(0.05), radius: 3, x: 0, y: 2)

                    // MARK: – About Card
                    VStack(alignment: .leading, spacing: 8) {
                        Text("About This Event")
                            .font(.headline)
                            .foregroundColor(.primary)
                        Text(event.description)
                            .font(.body)
                            .foregroundColor(.primary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)
                    .shadow(color: Color.black.opacity(0.05), radius: 3, x: 0, y: 2)

                    // MARK: – More Info or Register Button
                    if event.isRegON {
                        NavigationLink(destination: EventRegistrationView(event: event)) {
                            Text("Register")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.orange)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                        .padding(.top, 16)
                    } else {
                        Button(action: {
                            if let url = URL(string: "https://www.nemausa.org/") {
                                UIApplication.shared.open(url)
                            }
                        }) {
                            Text("More Information")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.orange)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                        .padding(.top, 16)
                    }
                }
                .padding()
                .background(Color(.systemBackground))
            }
        }
        .navigationTitle("Event Details")
        .navigationBarTitleDisplayMode(.inline)
        .accentColor(.white)  // ensure back‐button & nav‐tint stay white
    }
}

