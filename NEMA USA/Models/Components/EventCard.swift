// EventCard.swift
// NEMA USA
// Created by Nina on 4/15/25.
// Updated by Sajith n 5/22/25 for dynamic image loading

import SwiftUI
import Kingfisher

struct EventCard: View {
    let event: Event
    let userStatuses: EventUserStatuses
    
    // Convenience initializer for backward compatibility
    init(event: Event) {
        self.event = event
        // PERFORMANCE: Default to no status to avoid expensive lookups
        self.userStatuses = EventUserStatuses(
            hasPurchasedTickets: false,
            hasRegisteredPrograms: false,
            hasWaitlistPrograms: false
        )
    }
    
    // Main initializer with status information
    init(event: Event, userStatuses: EventUserStatuses) {
        self.event = event
        self.userStatuses = userStatuses
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // MARK: - Image with Status Tags Overlay
            ZStack(alignment: .topTrailing) {
                // Image
                let placeholderImageName = "DefaultEventImage"

                if let imageUrlString = event.imageUrl, let imageURL = URL(string: imageUrlString) {
                    let processor = DownsamplingImageProcessor(size: CGSize(width: 1200, height: 1200))
                    KFImage(imageURL)
                        .setProcessor(processor)
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
                
                // PERFORMANCE: Only show status tags if there are any
                if userStatuses.hasPurchasedTickets || userStatuses.hasRegisteredPrograms || userStatuses.hasWaitlistPrograms {
                    HStack(spacing: 6) {
                        if userStatuses.hasPurchasedTickets {
                            StatusTag(text: "Purchased", color: .green)
                        }
                        if userStatuses.hasRegisteredPrograms {
                            StatusTag(text: "Registered", color: .blue)
                        }
                        if userStatuses.hasWaitlistPrograms {  // ADD THIS
                            StatusTag(text: "Waitlisted", color: .orange)
                        }
                    }
                    .padding(8)
                }
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

            // Location
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
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 3, x: 0, y: 2)
    }
}

// MARK: - Supporting Views and Models

struct EventUserStatuses: Equatable {
    let hasPurchasedTickets: Bool
    let hasRegisteredPrograms: Bool
    let hasWaitlistPrograms: Bool
}

struct StatusTag: View {
    let text: String
    let color: Color
    
    var body: some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.bold)
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color)
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
    }
}

extension String {
    // Strips HTML tags to provide a clean plain text summary
    func stripHTML() -> String {
        return self.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression, range: nil)
    }
}
