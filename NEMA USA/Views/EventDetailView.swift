//
//  EventDetailView.swift
//  NEMA USA
//  Created by Nina on 4/16/25.
//  Updated by Sajith on 4/22/25
//

import SwiftUI
import UIKit
import Kingfisher

// MARK: - Subviews (File Private for Encapsulation)

fileprivate struct EventTitleCategoryView: View {
    let title: String
    let categoryName: String?

    var body: some View {
        VStack(alignment: .leading) {
            Text(title)
                .font(.title2).bold()
                .foregroundColor(.primary)

            Text(categoryName ?? "Uncategorized")
                .font(.subheadline).italic()
                .foregroundColor(.secondary)
        }
    }
}

fileprivate struct EventImageView: View {
    let imageUrlString: String?
    let placeholderImageName = "DefaultEventImage"

    var body: some View {
        if let imageUrlString = imageUrlString, let imageURL = URL(string: imageUrlString) {
            KFImage(imageURL)
                .placeholder {
                    Image(placeholderImageName)
                        .resizable()
                        .scaledToFit() // Changed from scaledToFill in placeholder to match original fallback
                        .frame(height: 200)
                        .background(Color.gray.opacity(0.1))
                        .clipped()
                        .cornerRadius(12)
                }
                .fade(duration: 0.25)
                .resizable()
                .scaledToFill()
                .frame(height: 200)
                .clipped()
                .cornerRadius(12)
        } else {
            Image(placeholderImageName)
                .resizable()
                .scaledToFit() // Consistent with above placeholder, might want to be scaledToFill if design dictates
                .frame(height: 200)
                .background(Color.gray.opacity(0.1))
                .clipped()
                .cornerRadius(12)
        }
    }
}

fileprivate struct EventDetailsCardView: View {
    let event: Event // Contains date, location

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .foregroundColor(.orange)
                Text("Date & Time")
                    .font(.headline)
                    .foregroundColor(.primary)
            }
            if let date = event.date { // Check if event.date has a value
                 Text([
                     date.formatted(.dateTime.month().day().year()),
                     date.formatted(.dateTime.hour().minute().locale(Locale.current))
                   ]
                   .compactMap { $0 } // Remove any nil components (if date formatting itself could return nil)
                   .joined(separator: " • ")
                 )
                 .font(.subheadline)
                 .foregroundColor(.primary)
             } else {
                 Text("To be Announced")
                     .font(.subheadline)
                     .foregroundColor(.primary)
             }

            Divider()

            HStack(spacing: 8) {
                Image(systemName: "mappin.and.ellipse")
                    .foregroundColor(.orange)
                Text("Location")
                    .font(.headline)
                    .foregroundColor(.primary)
            }
            Text(event.location ?? "To be Announced")
                .font(.subheadline)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: {
                // Assuming MapAppLauncher is globally accessible or defined elsewhere
                MapAppLauncher.presentMapOptions(for: event.location ?? "To be Announced")
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "location.fill")
                    Text("View on Map")
                }
            }
            .font(.subheadline.bold())
            .foregroundColor(.orange)
            .buttonStyle(PlainButtonStyle())
            .tint(Color.orange)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 3, x: 0, y: 2)
    }
}

fileprivate struct EventAboutCardView: View {
    let descriptionText: String // Changed name from 'description' to avoid conflict with View.description

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("About This Event")
                .font(.headline)
                .foregroundColor(.primary)
            Text(descriptionText)
                .font(.body)
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 3, x: 0, y: 2)
    }
}

fileprivate struct EventActionButtonsView: View {
    let event: Event // Needed for isRegON, eventLink and for NavigationLink destination

    var body: some View {
        Group { // Use Group if the outer padding/frame is handled by the parent VStack
            if event.isRegON ?? false {
                NavigationLink(destination: EventRegistrationView(event: event)) {
                    Text("Purchase Tickets")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
            } else {
                Button(action: {
                    let linkString = (event.eventLink?.isEmpty == false)
                        ? event.eventLink!
                        : "https://www.nemausa.org/events"
                    if let url = URL(string: linkString) {
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
            }
        }
        .padding(.top, 16) // Original padding applied here
    }
}

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
        UIView.appearance(whenContainedInInstancesOf: [UIAlertController.self]).tintColor = UIColor(Color.orange)
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Orange status‑bar wedge
            Color.orange
                .ignoresSafeArea(edges: .top)
                .frame(height: 56)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {

                    EventTitleCategoryView(title: event.title, categoryName: event.categoryName)

                    EventImageView(imageUrlString: event.imageUrl)

                    EventDetailsCardView(event: event)

                    EventAboutCardView(descriptionText: event.description ?? "")

                    EventActionButtonsView(event: event)
                }
                .padding()
                .background(Color(.systemBackground)) // Original background
            }
        }
        .navigationTitle("Event Details")
        .navigationBarTitleDisplayMode(.inline)
        .accentColor(.white)
    }
} // end of file

