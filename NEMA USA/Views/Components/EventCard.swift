//
//  EventCard.swift
//  NEMA USA
//  Created by Nina on 4/15/25.
//

import SwiftUI
import MapKit
import UIKit

struct EventCard: View {
    let event: Event

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // MARK: – Local Asset Image
            Group {
                // strip “.png” if it's there
                let assetName = event.imageUrl
                    .replacingOccurrences(of: ".png", with: "")
                if UIImage(named: assetName) != nil {
                    Image(assetName)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 180)
                        .clipped()
                        .cornerRadius(10)
                } else {
                    // fallback placeholder if the asset is missing
                    Color.gray.opacity(0.3)
                        .frame(height: 180)
                        .cornerRadius(10)
                }
            }

            // MARK: – Title
            Text(event.title)
                .font(.headline)
                .foregroundColor(.primary)

            // MARK: – Date / TBD
            Text(event.isTBD
                 ? "📅 To be announced"
                 : "📅 \(event.date?.formatted(date: .abbreviated, time: .omitted) ?? "")"
            )
            .font(.subheadline)
            .foregroundColor(.secondary)

            // MARK: – Location
            Button(action: {
                MapAppLauncher.presentMapOptions(for: event.location)
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "mappin.and.ellipse")
                        .foregroundColor(.secondary)
                    Text(event.location)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .buttonStyle(PlainButtonStyle())

            // MARK: – Description
            Text(event.description)
                .font(.body)
                .foregroundColor(.secondary)
                .lineLimit(2)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 3, x: 0, y: 2)
    }
}
