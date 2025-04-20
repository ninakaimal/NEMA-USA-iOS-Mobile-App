// EventDetailView.swift
// NEMA USA
// Created by Nina on 4/16/25.

import SwiftUI
import UIKit

struct EventDetailView: View {
    let event: Event

    init(event: Event) {
        self.event = event
        // Configure navigation bar appearance
        if #available(iOS 15.0, *) {
            let appearance = UINavigationBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = UIColor.orange
            appearance.titleTextAttributes = [.foregroundColor: UIColor.white]
            appearance.largeTitleTextAttributes = [.foregroundColor: UIColor.white]

            // White back-button text
            let backItemAppearance = UIBarButtonItemAppearance()
            backItemAppearance.normal.titleTextAttributes = [.foregroundColor: UIColor.white]
            appearance.backButtonAppearance = backItemAppearance

            // White back-indicator arrow
            if let arrow = UIImage(systemName: "chevron.backward")?.withTintColor(.white, renderingMode: .alwaysOriginal) {
                appearance.setBackIndicatorImage(arrow, transitionMaskImage: arrow)
            }

            UINavigationBar.appearance().standardAppearance = appearance
            UINavigationBar.appearance().scrollEdgeAppearance = appearance
            UINavigationBar.appearance().compactAppearance = appearance
            UINavigationBar.appearance().compactScrollEdgeAppearance = appearance
        } else {
            // Fallback
            UINavigationBar.appearance().barTintColor = .orange
            UINavigationBar.appearance().titleTextAttributes = [.foregroundColor: UIColor.white]
            UIBarButtonItem.appearance().tintColor = .white
            UIBarButtonItem.appearance().setTitleTextAttributes([.foregroundColor: UIColor.white], for: .normal)

            // Fallback arrow
            UINavigationBar.appearance().backIndicatorImage = UIImage(systemName: "chevron.backward")?.withTintColor(.white, renderingMode: .alwaysOriginal)
            UINavigationBar.appearance().backIndicatorTransitionMaskImage = UIImage(systemName: "chevron.backward")?.withTintColor(.white, renderingMode: .alwaysOriginal)
        }
        // Tint for other bar items
        UINavigationBar.appearance().tintColor = .white
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.orange
                .ignoresSafeArea(edges: .top)
                .frame(height: 56)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Title & Category
                    Text(event.title)
                        .font(.title2).bold()
                        .foregroundColor(.primary)
                    Text(event.category)
                        .font(.subheadline).italic()
                        .foregroundColor(.secondary)

                    // Event Image
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

                    // Details Card
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

                    // About Card
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

                    // More Info Button
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
                .padding()
                .background(Color(.systemBackground))
            }
        }
        .navigationTitle("Event Details")
        .navigationBarTitleDisplayMode(.inline)
        .accentColor(.white)
    }
}

