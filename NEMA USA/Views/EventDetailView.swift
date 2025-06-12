//
//  EventDetailView.swift
//  NEMA USA
//  Created by Nina on 4/16/25.
//  Updated by Sajith on 4/22/25
//

import SwiftUI
import Kingfisher

struct SectionTitleStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.headline)
            .foregroundColor(Color.primary)
    }
}

extension View {
    func sectionTitleStyle() -> some View {
        self.modifier(SectionTitleStyle())
    }
}

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
                    .sectionTitleStyle()
            }
            if let date = event.date {
                // If we have a valid Date object, format it.
                let dateString = date.formatted(date: .long, time: .omitted)
                // Use the specific time string from the API, with a fallback.
                let timeToDisplay = event.timeString ?? "Time To Be Announced"
                Text("\(dateString) • \(timeToDisplay)")
                    .font(.subheadline)
                    .foregroundColor(.primary)
            } else {
                // If the main date object is nil, just show the time string if it exists.
                Text(event.timeString ?? "Date & Time To be Announced")
                    .font(.subheadline)
                    .foregroundColor(.primary)
            }
            
            Divider()
            
            HStack(spacing: 8) {
                Image(systemName: "mappin.and.ellipse")
                    .foregroundColor(.orange)
                Text("Location")
                    .sectionTitleStyle()
            }
            Text(event.location ?? "To be Announced")
                .font(.subheadline)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
            
            if let location = event.location,
               !location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               location.lowercased() != "to be announced" {
                Button(action: {
                    // Assuming MapAppLauncher is globally accessible or defined elsewhere
                    MapAppLauncher.presentMapOptions(for: location)
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
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 3, x: 0, y: 2)
    }
}

struct HTMLRichText: View {
    let html: String

    var body: some View {
        Text(createAttributedString())
    }
    
    private func createAttributedString() -> AttributedString {
        // We prepend a CSS style block to the HTML.
        // This sets a default font and color but allows inline styles
        // from your HTML (e.g., style="color:red;") to take precedence.
        let styledHTML = """
        <style>
            body {
                font-family: -apple-system, sans-serif;
                font-size: \(UIFont.preferredFont(forTextStyle: .body).pointSize)px;
                color: \(UIColor.label.toHex());
            }
        </style>
        \(html)
        """
        
        guard let data = styledHTML.data(using: .utf8),
              let nsAttributedString = try? NSAttributedString(
                  data: data,
                  options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue],
                  documentAttributes: nil
              )
        else {
            return AttributedString()
        }
        
        return AttributedString(nsAttributedString)
    }
}

extension UIColor {
    func toHex() -> String {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        guard self.getRed(&r, green: &g, blue: &b, alpha: &a) else {
            return "#000000" // Default to black on failure
        }
        return String(format: "#%02x%02x%02x", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}

fileprivate struct DescriptionCardView: View {
    let title: String
    let content: String
    let isHTML: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .foregroundColor(.orange)
                Text(title)
                    .sectionTitleStyle()
            }
            .padding(.bottom, 4)
            
            if isHTML {
                HTMLRichText(html: content)
            } else {
                Text(content)
                    .font(.body)
                    .foregroundColor(.primary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 3, x: 0, y: 2)
    }
}


fileprivate struct EventActionButtonsView: View {
    let event: Event // Needed for isRegON, eventLink and for NavigationLink destination
    
    var body: some View {
        VStack(spacing: 15) {
            // This logic correctly handles all combinations of ticketing and registration
            var didShowPrimaryButton = false
            
            // Case 1: Ticketing is ON
            if event.isTktON == true {
                NavigationLink(destination: EventRegistrationView(event: event)) {
                    Text("Purchase Tickets")
                        .font(.headline).fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                // Mark that we showed a button
                let _ = { didShowPrimaryButton = true }()
            }
            // Case 2: Registration is ON
            if event.isRegON == true {
                // NOTE: This currently navigates to a placeholder view.
                // You can replace this destination with your actual registration view in the future.
                NavigationLink(destination: Text("Registration Form for \(event.title)")) {
                    Text("Register Now")
                        .font(.headline).fontWeight(.semibold)
                        .frame(maxWidth: .infinity).padding()
                        .background(Color.blue) // Use a different color to distinguish it
                        .foregroundColor(.white).cornerRadius(10)
                }
                // Mark that we showed a button
                let _ = { didShowPrimaryButton = true }()
            }
            // Case 3: NEITHER ticketing nor registration is ON
            if !didShowPrimaryButton {
                Text("Ticketing Closed")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.gray) // Use a distinct disabled color
                    .foregroundColor(.white)
                    .cornerRadius(10)
                // Show the "More Information" button as a fallback if a link exists
                if let link = event.eventLink, let url = URL(string: link), !link.isEmpty {
                    Button(action: {
                        UIApplication.shared.open(url)
                    }) {
                        Text("More Information")
                            .font(.subheadline).fontWeight(.semibold)
                            .frame(maxWidth: .infinity).padding()
                            .background(Color.secondary.opacity(0.2))
                            .foregroundColor(.primary)
                            .cornerRadius(10)
                    }
                }
            }
        }
        .padding(.top, 16)              
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

                    // Card 1: For the plain text description
                    if let plainDesc = event.plainDescription, !plainDesc.isEmpty {
                        DescriptionCardView(title: "About This Event", content: plainDesc, isHTML: false)
                    }
                    
                    // Card 2: For the HTML description/guidelines
                    if let htmlDesc = event.htmlDescription, !htmlDesc.isEmpty {
                        DescriptionCardView(title: "Additional Details", content: htmlDesc, isHTML: true)
                    }

                    EventActionButtonsView(event: event)
                }
                .padding()
                .background(Color(.systemBackground))
            }
        }
        .navigationTitle("Event Details")
        .navigationBarTitleDisplayMode(.inline)
        .accentColor(.white)
    }
} // end of file

