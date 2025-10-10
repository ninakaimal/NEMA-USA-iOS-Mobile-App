//
//  EventDetailView.swift
//  NEMA USA
//  Created by Nina on 4/16/25.
//  Updated by Sajith on 4/22/25
//  Updated by Sajith on 8/14/25 - added sub-events for Drishya

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
    @Published var error: String?
    
    private let repository = EventRepository()
    private var loadingTask: Task<Void, Never>?
    
    deinit {
        loadingTask?.cancel()
    }
    
    func loadPrograms(for eventId: String) async {
        // Cancel any existing task
        loadingTask?.cancel()
        
        guard !isLoading else { return }
        isLoading = true
        error = nil
        
        loadingTask = Task { @MainActor in
            do {
                // Use the new async method with timeout
                self.programs = try await withTimeout(seconds: 10) {
                    await self.repository.syncProgramsAsync(for: eventId)
                }
            } catch TimeoutError.timeout {
                self.error = "Loading timed out. Please try again."
                print("⚠️ Program loading timed out for event \(eventId)")
            } catch {
                self.error = "Failed to load programs."
                print("⚠️ Error loading programs: \(error)")
            }
            self.isLoading = false
        }
        await loadingTask?.value
    }
}

// Timeout utility
enum TimeoutError: Error {
    case timeout
}

func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
    return try await withThrowingTaskGroup(of: T.self) { group in
        // Add the main operation
        group.addTask {
            try await operation()
        }
        
        // Add timeout task
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw TimeoutError.timeout
        }
        
        // Return first completed result and cancel others
        let result = try await group.next()!
        group.cancelAll()
        return result
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
    @Binding var showLoginSheet: Bool
    @Binding var pendingPurchaseAfterLogin: Bool
    
    var body: some View {
        //let _ = print("DEBUG: Checking button for event '\(event.title)'. showBuyTickets=\(event.showBuyTickets ?? false), isTktON=\(event.isTktON ?? false)")
        VStack(spacing: 15) {
            if event.showBuyTickets == true {
                if event.isRegON == true {
                    // Check if tickets are waitlisted
                    let buttonText = (event.isRegWaitlist == true) ? "Join Waitlist" : "Purchase Tickets"
                    let buttonColor = (event.isRegWaitlist == true) ? Color.orange : Color.orange

                    // Case 1A: Ticketing is ON or on Waitlist. Show the appropriate button.
                    // Force login before allowing ticket purchase
                    if DatabaseManager.shared.jwtApiToken == nil {
                        Button(action: {
                            pendingPurchaseAfterLogin = true
                            showLoginSheet = true
                        }) {
                            Text("Login to Purchase Tickets")
                                .font(.headline)
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.orange)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                    } else {
                        NavigationLink(destination: EventRegistrationView(event: event)) {
                            Text(buttonText)
                                .font(.headline)
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.orange)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                    }
                } else {
                    // Case 1B: Ticketing is OFF. Show the "Ticketing Closed" button.
                    Text("Ticketing Closed")
                        .font(.headline).fontWeight(.semibold).frame(maxWidth: .infinity).padding()
                        .background(Color.gray).foregroundColor(.white).cornerRadius(10)
                }
            }
            // Case 2: This is a non-ticketed, "Register Now" event.
            else if event.isRegON == true && !hasPrograms {
                NavigationLink(destination: Text("Registration Form for \(event.title)")) {
                    Text("Register Now")
                        .font(.headline).fontWeight(.semibold).frame(maxWidth: .infinity).padding()
                        .background(Color.blue).foregroundColor(.white).cornerRadius(10)
                }
            }
            // Case 3: This is a non-ticketed event that is closed for registration.
            else if !hasPrograms {
                Text("Registration Closed")
                    .font(.headline).fontWeight(.semibold).frame(maxWidth: .infinity).padding()
                    .background(Color.gray).foregroundColor(.white).cornerRadius(10)
            }

            // The "More Information" button
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

// NEW: Sub-events expanded view component
struct SubEventsExpandedView: View {
    let subEvents: [Event]
    let isLoading: Bool
    let error: String?
    @Binding var programToRegister: EventProgram?
    @Binding var showLoginSheet: Bool
    @Binding var pendingPurchaseAfterLogin: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "calendar.badge.plus")
                    .foregroundColor(.orange)
                Text("Event Days")
                    .font(.headline)
                    .foregroundColor(.primary)
            }
            .padding(.bottom, 4)
            
            if isLoading {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading event days...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity)
            } else if let error = error {
                Text(error)
                    .font(.subheadline)
                    .foregroundColor(.red)
                    .padding(.vertical, 20)
            } else if subEvents.isEmpty {
                // Don't show anything if no sub-events (this is a regular event)
                EmptyView()
            } else {
                // Display each sub-event as a full event card
                ForEach(subEvents) { subEvent in
                    SubEventFullCard(
                        subEvent: subEvent,
                        programToRegister: $programToRegister,
                        showLoginSheet: $showLoginSheet,
                        pendingPurchaseAfterLogin: $pendingPurchaseAfterLogin
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 3, x: 0, y: 2)
    }
}

// NEW: Individual sub-event card (rendered exactly like main event)
struct SubEventFullCard: View {
    let subEvent: Event
    @Binding var programToRegister: EventProgram?
    @Binding var showLoginSheet: Bool
    @Binding var pendingPurchaseAfterLogin: Bool
    @StateObject private var programsViewModel = EventProgramsViewModel()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Sub-event title and details
            VStack(alignment: .leading, spacing: 8) {
                Text(subEvent.title)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                if let date = subEvent.date {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .foregroundColor(.orange)
                        Text(date.formatted(date: .long, time: .omitted))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                
                if let timeString = subEvent.timeString, !timeString.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .foregroundColor(.orange)
                        Text(timeString)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                
                if let location = subEvent.location {
                    HStack(spacing: 4) {
                        Image(systemName: "mappin.and.ellipse")
                            .foregroundColor(.orange)
                        Text(location)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // Sub-event description
            if let plainDesc = subEvent.plainDescription, !plainDesc.isEmpty {
                Text(plainDesc)
                    .font(.body)
                    .foregroundColor(.primary)
            }
            
            // Sub-event programs (exactly like main event)
            if programsViewModel.isLoading || !programsViewModel.programs.isEmpty {
                CompetitionsCardView(
                    viewModel: programsViewModel,
                    programToRegister: $programToRegister,
                    showLoginSheet: $showLoginSheet
                )
            }
            
            // Sub-event action buttons (exactly like main event)
            EventActionButtonsView(
                event: subEvent,
                hasPrograms: !programsViewModel.programs.isEmpty,
                showLoginSheet: $showLoginSheet,
                pendingPurchaseAfterLogin: $pendingPurchaseAfterLogin
            )
        }
        .padding()
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(8)
        .task {
            await programsViewModel.loadPrograms(for: subEvent.id)
        }
    }
}

struct EventDetailView: View {
    let event: Event
    
    // State Object - Create an instance of the new ViewModel
    @StateObject private var programsViewModel = EventProgramsViewModel()
    @State private var programToRegister: EventProgram?
    @State private var showLoginSheet = false
    @State private var navigateToPurchase = false    // controls the hidden NavigationLink
    @State private var pendingPurchaseAfterLogin = false // remember why we opened Login
    
    // Sub-events properties
    @State private var subEvents: [Event] = []
    @State private var isLoadingSubEvents = false
    @State private var subEventsError: String?
    
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
                    
                    // NEW: Sub-events as full-width cards (no container card)
                    if isLoadingSubEvents {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Loading event days...")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 20)
                        .frame(maxWidth: .infinity)
                    } else if let error = subEventsError {
                        Text(error)
                            .font(.subheadline)
                            .foregroundColor(.red)
                            .padding(.vertical, 20)
                    } else if !subEvents.isEmpty {
                        // Display each sub-event as individual full-width cards
                        ForEach(subEvents) { subEvent in
                            SubEventFullWidthCard(
                                subEvent: subEvent,
                                programToRegister: $programToRegister,
                                showLoginSheet: $showLoginSheet,
                                pendingPurchaseAfterLogin: $pendingPurchaseAfterLogin
                            )                        }
                    }
                    
                    // Card 3: For main event Competitions and performances (only if no sub-events)
                    if subEvents.isEmpty && !isLoadingSubEvents && (programsViewModel.isLoading || !programsViewModel.programs.isEmpty) {
                        CompetitionsCardView(
                            viewModel: programsViewModel,
                            programToRegister: $programToRegister,
                            showLoginSheet: $showLoginSheet
                        )
                    }
                    
                    // Hidden NavigationLink that triggers programmatically after login
                    NavigationLink(
                        destination: EventRegistrationView(event: event),
                        isActive: $navigateToPurchase
                    ) { EmptyView() }
                    .hidden()
                    
                    // Action buttons (only for events without sub-events)
                    if subEvents.isEmpty && !isLoadingSubEvents {
                        EventActionButtonsView(
                            event: event,
                            hasPrograms: !programsViewModel.programs.isEmpty,
                            showLoginSheet: $showLoginSheet,
                            pendingPurchaseAfterLogin: $pendingPurchaseAfterLogin
                        )
                    }
                }
                .padding()
                .background(Color(.systemBackground))
            }
        }
        
        .onReceive(NotificationCenter.default.publisher(for: .didReceiveJWT)) { _ in
            // 1) Existing: program registration flow
            if self.programToRegister != nil {
                print("Login successful, proceeding with registration flow.")
                self.showLoginSheet = false // Dismiss the login sheet; the .sheet(item:) will present the registration UI
            }

            // 2) New: ticket purchase flow
            if pendingPurchaseAfterLogin {
                pendingPurchaseAfterLogin = false
                showLoginSheet = false
                // Give the sheet a moment to dismiss before navigating
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    navigateToPurchase = true
                }
            }
        }
        .sheet(isPresented: $showLoginSheet, onDismiss: {
            // This code runs when the LoginView is dismissed. We check if the user is STILL not logged in.
            if DatabaseManager.shared.jwtApiToken == nil {
                // If they aren't logged in, it means they cancelled. We must reset the state to cancel the registration flow.
                print("[EventDetailView] Login sheet dismissed without login. Cancelling registration flow.")
                self.programToRegister = nil
            }
        }) {
            LoginView()
        }
        .navigationTitle("Event Details")
        .navigationBarTitleDisplayMode(.inline)
        .accentColor(.white)
        .onAppear {
            Task {
                await programsViewModel.loadPrograms(for: event.id)
                await loadSubEvents()
            }
        }
        .sheet(item: $programToRegister) { program in
            // This now gets triggered correctly after the login sheet is dismissed.
            ProgramRegistrationView(event: event, program: program)
        }
    }
    
    // NEW: Load sub-events method
    private func loadSubEvents() async {
        isLoadingSubEvents = true
        subEventsError = nil
        
        do {
            let fetchedSubEvents = try await NetworkManager.shared.fetchSubEvents(forParentEventId: event.id)
            await MainActor.run {
                self.subEvents = fetchedSubEvents
                self.isLoadingSubEvents = false
                print("✅ [EventDetailView] Loaded \(fetchedSubEvents.count) sub-events for parent event \(event.id)")
            }
        } catch {
            await MainActor.run {
                // Only show error if we expected sub-events (you could add logic to check if parent has children)
                if case NetworkError.serverError(let message) = error, !message.contains("404") {
                    self.subEventsError = "Failed to load event days: \(error.localizedDescription)"
                    print("❌ [EventDetailView] Error loading sub-events: \(error)")
                }
                self.isLoadingSubEvents = false
            }
        }
    }
}

// Sub-event card with image
struct SubEventFullWidthCard: View {
    let subEvent: Event
    @Binding var programToRegister: EventProgram?
    @Binding var showLoginSheet: Bool
    @Binding var pendingPurchaseAfterLogin: Bool
    
    // Replace @StateObject with @State for direct control
    @State private var programs: [EventProgram] = []
    @State private var isLoadingPrograms = false
    @State private var programsError: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Sub-event title
            Text(subEvent.title)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            
            // Sub-event image (just like main event)
            EventImageView(imageUrlString: subEvent.imageUrl)
            
            // Sub-event details card (similar to main event)
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "calendar")
                        .foregroundColor(.orange)
                    Text("Date & Time")
                        .sectionTitleStyle()
                }
                
                if let date = subEvent.date {
                    let dateString = date.formatted(date: .long, time: .omitted)
                    let timeToDisplay = subEvent.timeString ?? "Time To Be Announced"
                    Text("\(dateString) • \(timeToDisplay)")
                        .font(.subheadline)
                        .foregroundColor(.primary)
                } else {
                    Text(subEvent.timeString ?? "Date & Time To be Announced")
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
                Text(subEvent.location ?? "To be Announced")
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                
                if let location = subEvent.location,
                   !location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   location.lowercased() != "to be announced" {
                    Button(action: {
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
            
            // Sub-event description
            if let plainDesc = subEvent.plainDescription, !plainDesc.isEmpty {
                DescriptionCardView(title: "About This Day", content: plainDesc, isHTML: false)
            }
            
            if let htmlDesc = subEvent.htmlDescription, !htmlDesc.isEmpty {
                DescriptionCardView(title: "Additional Details", content: htmlDesc, isHTML: true)
            }
            
            // Sub-event programs - use direct state instead of ViewModel
            if isLoadingPrograms || !programs.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) {
                        Image(systemName: "flag.2.crossed.fill").foregroundColor(.orange)
                        Text("Competitions & Performances").sectionTitleStyle()
                    }
                    .padding([.horizontal, .top]).padding(.bottom, 8)
                    
                    Divider().padding(.horizontal)
                    
                    if isLoadingPrograms && programs.isEmpty {
                        ProgressView().frame(maxWidth: .infinity).padding()
                    } else if !programs.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(programs) { program in
                                VStack {
                                    EventProgramRowView(program: program, programToRegister: $programToRegister, showLoginSheet: $showLoginSheet)
                                    if program.id != programs.last?.id { Divider().padding(.horizontal) }
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
            
            // Sub-event action buttons (exactly like main event)
            EventActionButtonsView(
                event: subEvent,
                hasPrograms: !programs.isEmpty,
                showLoginSheet: $showLoginSheet,
                pendingPurchaseAfterLogin: $pendingPurchaseAfterLogin
            )
        }
        .task {
            // Use direct NetworkManager call instead of EventProgramsViewModel
            await loadPrograms()
        }
    }
    
    // Direct programs loading method
    private func loadPrograms() async {
        isLoadingPrograms = true
        programsError = nil
        
        do {
            let fetchedPrograms = try await NetworkManager.shared.fetchPrograms(forEventId: subEvent.id)
            await MainActor.run {
                self.programs = fetchedPrograms
                self.isLoadingPrograms = false
            }
        } catch {
            await MainActor.run {
                self.programsError = error.localizedDescription
                self.isLoadingPrograms = false
            }
        }
    }
}

// NEW HELPER VIEW: WrappingHStack for the flowing category tags.
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
