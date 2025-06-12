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
                .lineLimit(1)
                .truncationMode(.tail)

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

            // --- Updated Location ---
            // The Button has been replaced with a non-interactive HStack
            // to prevent the map picker from appearing on this view.
            HStack(spacing: 4) {
                Image(systemName: "mappin.and.ellipse")
                    .foregroundColor(.secondary)
                Text(event.location ?? "To be Announced")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            // Description - Removed description from the Event card
//            Text(event.description?.stripHTML() ?? "")
//                .font(.body)
//                .foregroundColor(.secondary)
//                .lineLimit(2)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 3, x: 0, y: 2)
    }
} // end of file

extension String {
    // Strips HTML tags to provide a clean plain text summary
    func stripHTML() -> String {
        return self.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression, range: nil)
    }
}
