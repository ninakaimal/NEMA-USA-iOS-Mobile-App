// EventCard.swift
// NEMA USA
// Created by Nina on 4/15/25.
// Updated by Sajith n 5/22/25 for dynamic image loading

import SwiftUI
import Kingfisher

struct EventCard: View {
    let event: Event

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // MARK: - Image (Dynamic Loading with Kingfisher)
            let placeholderImageName = "DefaultEventImage" // Make sure this asset exists

            if let imageUrlString = event.imageUrl, let imageURL = URL(string: imageUrlString) {
                KFImage(imageURL)
                    .placeholder {
                        Image(placeholderImageName)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 180)
                            .background(Color.gray.opacity(0.1))
                            .clipped()
                            .cornerRadius(10)
                    }
                    .fade(duration: 0.25)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 180)
                    .clipped()
                    .cornerRadius(10)
            } else {
                // Fallback if imageUrl is nil or not a valid URL
                Image(placeholderImageName)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 180)
                    .background(Color.gray.opacity(0.1))
                    .clipped()
                    .cornerRadius(10)
            }

            // Title
            Text(event.title)
                .font(.headline)
                .foregroundColor(.primary)

            // Date
            if let date = event.date {
                Text("📅 \(date.formatted(date: .abbreviated, time: .omitted))")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                Text("📅 To be announced")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            // Location
            Button(action: {
                // Assuming event.location is non-optional as per Event.swift
                MapAppLauncher.presentMapOptions(for: event.location ?? "To be Announced")
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "mappin.and.ellipse")
                        .foregroundColor(.secondary)
                    Text(event.location ?? "To be Announced")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .buttonStyle(PlainButtonStyle())

            // Description
            Text(event.description ?? "")
                .font(.body)
                .foregroundColor(.secondary)
                .lineLimit(2)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 3, x: 0, y: 2)
    }
} // end of file
