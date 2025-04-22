//
//  EventDetailView.swift
//  NEMA USA
//  Created by Nina on 4/16/25.
//  Updated by Arjun on 4/23/25
//

import SwiftUI
import UIKit

struct EventDetailView: View {
    let event: Event

    var body: some View {
        ZStack(alignment: .top) {
            // Top orange header
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

                } // end VStack
                .padding()
                .background(Color(.systemBackground))
            } // end ScrollView
        } // end ZStack
        .navigationTitle("Event Details")
        .navigationBarTitleDisplayMode(.inline)
        // ↓ Removed the per‑view .accentColor(.white) here
    }
}

