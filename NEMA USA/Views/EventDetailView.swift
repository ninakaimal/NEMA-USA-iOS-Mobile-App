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

// ViewModel manages fetching and storing the programs for the detail view

@MainActor
class EventProgramsViewModel: ObservableObject {
    @Published var programs: [EventProgram] = []
    @Published var isLoading = false
    
    private let repository = EventRepository()
    
    func loadPrograms(for eventId: String) async {
        guard !isLoading else { return }
        isLoading = true
        self.programs = await repository.syncPrograms(forEventID: eventId)
        isLoading = false
    }
}



// UI COMPONENT 2: The main card that holds the list of programs.
fileprivate struct CompetitionsCardView: View {
    @ObservedObject var viewModel: EventProgramsViewModel
    @Binding var programToRegister: EventProgram?
    @Binding var showLoginSheet: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "flag.2.crossed.fill").foregroundColor(.orange)
                Text("Competitions & Performances").sectionTitleStyle()
            }
            .padding([.horizontal, .top]).padding(.bottom, 8)
            
            Divider().padding(.horizontal)

            if viewModel.isLoading && viewModel.programs.isEmpty {
                ProgressView().frame(maxWidth: .infinity).padding()
            } else if !viewModel.programs.isEmpty {
                VStack(spacing: 0) {
                    ForEach(viewModel.programs) { program in
                        VStack {
                            EventProgramRowView(program: program,programToRegister: $programToRegister,showLoginSheet: $showLoginSheet)
                            if program.id != viewModel.programs.last?.id { Divider().padding(.horizontal) }
                        }
                        .padding(.horizontal)
                    }
                }
            } else {
                Text("No specific programs listed for this event.")
                    .font(.subheadline).foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center).padding()
            }
        }
        .background(Color(.secondarySystemBackground)).cornerRadius(12).shadow(color: Color.black.opacity(0.05), radius: 3, x: 0, y: 2)
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
                .downsampling(size: CGSize(width: 1200, height: 1200))
                .placeholder {
                    Image(placeholderImageName)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 200)
                        .background(Color.gray.opacity(0.1))
                        .clipped()
                        .cornerRadius(12)
                }
                .scaleFactor(UIScreen.main.scale)
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

// UI COMPONENT 1: A view for a single row in the new card.
fileprivate struct EventProgramRowView: View {
    let program: EventProgram
    
    @Binding var programToRegister: EventProgram?
    @Binding var showLoginSheet: Bool
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Program Title, Time, and Categories
            HStack {
                VStack(alignment: .leading) {
                    Text(program.name).font(.headline.weight(.medium))
                    if let time = program.time, !time.isEmpty {
                        Text(time).font(.caption).foregroundColor(.secondary)
                    }
                    // Display categories in a flow-like layout
                    if !program.categories.isEmpty {
                        WrappingHStack(id: \.id, data: program.categories, alignment: .leading, horizontalSpacing: 4, verticalSpacing: 4) { category in
                            Text(category.name)
                                .font(.caption2).padding(.horizontal, 6).padding(.vertical, 3)
                                .background(Color.orange.opacity(0.1)).foregroundColor(.orange).cornerRadius(6)
                        }
                        .padding(.top, 4)
                    }
                }

                Spacer()
                // Registration Status
                Button(action: {
                    // First, set which program the user intends to register for.
                    self.programToRegister = program
                    // Now, check if the user is logged in.
                    if DatabaseManager.shared.jwtApiToken == nil {
                        // If not logged in, show the login sheet.
                        // After login, the .onReceive modifier will handle the rest.
                        self.showLoginSheet = true
                    }
                    
                }) {
                    Text(program.registrationStatus ?? "N/A")
                        .font(.caption.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(
                            (program.registrationStatus == "Click to Register" || program.registrationStatus == "Join Waitlist") ? Color.orange : Color.gray
                        )
                        .clipShape(Capsule())
                }
                .disabled(!(program.registrationStatus == "Click to Register" || program.registrationStatus == "Join Waitlist"))
            }

            // Rules and Guidelines expander
            if let rules = program.rulesAndGuidelines, !rules.isEmpty {
                Button(action: {
                    withAnimation { isExpanded.toggle() }
                }) {
                    HStack {
                        Text("Rules and Guidelines")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.orange)
                }
                .padding(.top, 8)
                
                if isExpanded {
                    HTMLRichText(html: rules)
                        .font(.body)
                        .padding(.top, 4)
                }
            }
        }
        .padding(.vertical, 8)
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
    let hasPrograms: Bool
    
    var body: some View {
        VStack(spacing: 15) {
            // Case 1: This is an event that has tickets.
            if event.showBuyTickets == true {
                if event.isTktON == true {
                    // And ticketing is currently open
                    NavigationLink(destination: EventRegistrationView(event: event)) {
                        Text("Purchase Tickets")
                            .font(.headline).fontWeight(.semibold).frame(maxWidth: .infinity).padding()
                            .background(Color.orange).foregroundColor(.white).cornerRadius(10)
                    }
                } else {
                    // Or ticketing is currently closed
                    Text("Ticketing Closed")
                        .font(.headline).fontWeight(.semibold).frame(maxWidth: .infinity).padding()
                        .background(Color.gray).foregroundColor(.white).cornerRadius(10)
                }
            }
            // Case 2: This is a non-ticketed, "Register Now" event (that does not have individual programs).
            else if event.isRegON == true && !hasPrograms {
                 NavigationLink(destination: Text("Registration Form for \(event.title)")) {
                    Text("Register Now")
                        .font(.headline).fontWeight(.semibold).frame(maxWidth: .infinity).padding()
                        .background(Color.blue).foregroundColor(.white).cornerRadius(10)
                }
            }
            // Case 3: This is a non-ticketed event that is closed for registration (and has no programs).
            else if !hasPrograms {
                Text("Registration Closed")
                    .font(.headline).fontWeight(.semibold).frame(maxWidth: .infinity).padding()
                    .background(Color.gray).foregroundColor(.white).cornerRadius(10)
            }

            // The "More Information" button can be shown as a universal fallback
            if let link = event.eventLink, let url = URL(string: link), !link.isEmpty {
                Button(action: { UIApplication.shared.open(url) }) {
                    Text("More Information")
                        .font(.subheadline).fontWeight(.semibold).frame(maxWidth: .infinity).padding()
                        .background(Color.secondary.opacity(0.2)).foregroundColor(.primary).cornerRadius(10)
                }
            }
        }
        .padding(.top, 16)
    }
}

struct EventDetailView: View {
    let event: Event
    
    // State Object - Create an instance of the new ViewModel
    @StateObject private var programsViewModel = EventProgramsViewModel()
    @State private var programToRegister: EventProgram?
    @State private var showLoginSheet = false
    
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
                    
                    // Card 3: For Competitions and performances
                    if programsViewModel.isLoading || !programsViewModel.programs.isEmpty {
                        CompetitionsCardView(viewModel: programsViewModel, programToRegister: $programToRegister, showLoginSheet: $showLoginSheet)
                    }
                    
                    EventActionButtonsView(event: event, hasPrograms: !programsViewModel.programs.isEmpty)
                }
                .padding()
                .background(Color(.systemBackground))
            }
        }
        
        .onReceive(NotificationCenter.default.publisher(for: .didReceiveJWT)) { _ in
            // After login, if programToRegister is not nil, it means the user was trying to register.
            // We set showLoginSheet to false and keep programToRegister set,
            // which will automatically trigger the .sheet(item:...) modifier.
            if self.programToRegister != nil {
                print("Login successful, proceeding with registration flow.")
                self.showLoginSheet = false // Dismiss the login sheet
            }
        }
        .sheet(isPresented: $showLoginSheet) {
            LoginView()
        }
        .navigationTitle("Event Details")
        .navigationBarTitleDisplayMode(.inline)
        .accentColor(.white)
        .onAppear {
            Task { await programsViewModel.loadPrograms(for: event.id) }
        }
        .sheet(item: $programToRegister) { program in
            // This now gets triggered correctly after the login sheet is dismissed.
            ProgramRegistrationView(event: event, program: program)
        }
    }
} // end of file

// NEW HELPER VIEW: Add this at the bottom of the file for the flowing category tags.

struct WrappingHStack<Data: RandomAccessCollection, Content: View>: View where Data.Element: Identifiable {
    let id: KeyPath<Data.Element, Data.Element.ID>
    let data: Data
    let content: (Data.Element) -> Content
    let alignment: HorizontalAlignment
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat
    
    @State private var totalHeight: CGFloat = .zero
    
    init(id: KeyPath<Data.Element, Data.Element.ID>, data: Data, alignment: HorizontalAlignment = .leading, horizontalSpacing: CGFloat = 8, verticalSpacing: CGFloat = 8, @ViewBuilder content: @escaping (Data.Element) -> Content) {
        self.id = id
        self.data = data
        self.alignment = alignment
        self.horizontalSpacing = horizontalSpacing
        self.verticalSpacing = verticalSpacing
        self.content = content
    }
    
    var body: some View {
        VStack {
            GeometryReader { geometry in
                self.generateContent(in: geometry)
            }
        }
        .frame(height: totalHeight)
    }
    
    private func generateContent(in g: GeometryProxy) -> some View {
        var width = CGFloat.zero
        var height = CGFloat.zero
        
        return ZStack(alignment: .topLeading) {
            ForEach(data) { item in
                self.content(item)
                    .padding(.horizontal, horizontalSpacing / 2)
                    .padding(.vertical, verticalSpacing / 2)
                    .alignmentGuide(alignment, computeValue: { d in
                        if (abs(width - d.width) > g.size.width) {
                            width = 0
                            height -= d.height
                        }
                        let result = width
                        if item[keyPath: id] == self.data.last?[keyPath: id] {
                            width = 0
                        } else {
                            width -= d.width
                        }
                        return result
                    })
                    .alignmentGuide(.top, computeValue: { d in
                        let result = height
                        if item[keyPath: id] == self.data.last?[keyPath: id] {
                            height = 0
                        }
                        return result
                    })
            }
        }
        .background(viewHeightReader($totalHeight))
    }
    
    private func viewHeightReader(_ binding: Binding<CGFloat>) -> some View {
        return GeometryReader { geometry -> Color in
            let rect = geometry.frame(in: .local)
            DispatchQueue.main.async {
                binding.wrappedValue = rect.size.height
            }
            return .clear
        }
    }
} // End of File
