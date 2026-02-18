// DashboardView.swift
    // NEMA USA
    // Created by Nina on 4/16/25.
    // Updated by Sajith on 5/22/25 for Core Data and API integration

import SwiftUI

struct DashboardView: View {
    // 1. Switch from EventLoader to EventRepository
    @StateObject private var eventRepository = EventRepository() // Initializes with default Core Data context
    @StateObject private var eventStatusService = EventStatusService.shared

    @State private var searchQuery = ""
    @State private var selectedCategory: String = "All"
    @FocusState private var isSearchFocused: Bool

    // Sponsors section remains unchanged
    let sponsors = ["sponsor1", "sponsor2", "sponsor3", "sponsor4", "sponsor5"]
    @State private var currentSponsor = 0
    private let sponsorTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    private var dashboardEvents: [Event] {
        eventRepository.events.filter { $0.parentEventId == nil }
    }

    var categories: [String] {
        let nonOptionalCats = dashboardEvents.compactMap { $0.categoryName }
        let uniqueSortedCats = Set(nonOptionalCats).sorted()
        return ["All"] + uniqueSortedCats
    }

    var filteredEvents: [Event] {
        dashboardEvents.filter { ev in
            let matchesSearch = searchQuery.isEmpty
                || ev.title.localizedCaseInsensitiveContains(searchQuery)
                // Use optional chaining and nil-coalescing for optional description and location
                || (ev.plainDescription?.localizedCaseInsensitiveContains(searchQuery) ?? false)
                || (ev.htmlDescription?.stripHTML().localizedCaseInsensitiveContains(searchQuery) ?? false)
                || (ev.location?.localizedCaseInsensitiveContains(searchQuery) ?? false)
            let matchesCat = selectedCategory == "All" || ev.categoryName == selectedCategory
            return matchesSearch && matchesCat
        }
    }
    var upcomingEvents: [Event] {
        filteredEvents
            .filter { event in // Use a more descriptive variable name
                if let date = event.date {
                    return date >= Calendar.current.startOfDay(for: Date()) // Event date is today or in the future
                }
                return true // If date is nil, it's TBD, so consider it upcoming
            }
            .sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
    }

    var pastEvents: [Event] {
        filteredEvents
            .filter { $0.date.map { $0 < Date() } ?? false } // Only past dates, not TBD
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) } // Show most recent past events first
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                BannerView() // Unchanged
                Spacer().frame(height: 16)

                // Search bar (Unchanged visually and functionally, just operates on new data source)
                HStack {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.gray)
                        TextField("Search events…", text: $searchQuery)
                            .focused($isSearchFocused)
                            .disableAutocorrection(true)
                            .foregroundColor(.primary)
                        if !searchQuery.isEmpty {
                            Button { searchQuery = "" } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                    .padding(14)
                    .background(Color(.systemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 25)
                            .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                    )
                    .padding(.horizontal)
                }
                .padding(.bottom, 12)

                // Category selector (Unchanged visually and functionally)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(categories, id: \.self) { cat in // 'categories' now uses eventRepository.events
                            Button(cat) { selectedCategory = cat }
                                .padding(.vertical, 10)
                                .padding(.horizontal, 16)
                                .background(selectedCategory == cat ? Color.orange : Color.white)
                                .foregroundColor(selectedCategory == cat ? .white : .black)
                                .cornerRadius(14)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                                )
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.bottom, 16)

                // Event lists & sponsors
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // 2. Added Loading and Error States display
                        if eventRepository.isLoading && upcomingEvents.isEmpty && pastEvents.isEmpty {
                            ProgressView("Loading Events...")
                                .padding(.top, 50)
                                .frame(maxWidth: .infinity)
                        } else if let errorMessage = eventRepository.lastSyncErrorMessage, upcomingEvents.isEmpty && pastEvents.isEmpty && !eventRepository.isLoading {
                             Text("Error: \(errorMessage)")
                                .foregroundColor(.red)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .center)
                        }

                        if !upcomingEvents.isEmpty {
                            Text("Upcoming Events")
                                .font(.title2).bold()
                                .foregroundColor(.primary)
                                .padding(.horizontal)
                            LazyVStack(spacing: 16) {
                                ForEach(upcomingEvents) { ev in // upcomingEvents now uses eventRepository.events
                                    NavigationLink(destination: EventDetailView(event: ev)) {
                                        // PERFORMANCE: Only show status for logged-in users
                                        if DatabaseManager.shared.jwtApiToken != nil {
                                            EventCard(
                                                event: ev,
                                                userStatuses: eventStatusService.getUserStatuses(for: ev)
                                            )
                                        } else {
                                            EventCard(event: ev) // No status lookup for guests
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 0.8) // subtle border
                            )
                        }

                        if !pastEvents.isEmpty {
                            Text("Past Events")
                                .font(.title2).bold()
                                .foregroundColor(.primary)
                                .padding(.horizontal)
                            LazyVStack(spacing: 16) {
                                ForEach(pastEvents) { ev in // pastEvents now uses eventRepository.events
                                    NavigationLink(destination: EventDetailView(event: ev)) {
                                        // PERFORMANCE: Only show status for logged-in users
                                        if DatabaseManager.shared.jwtApiToken != nil {
                                            EventCard(
                                                event: ev,
                                                userStatuses: eventStatusService.getUserStatuses(for: ev)
                                            )
                                        } else {
                                            EventCard(event: ev) // No status lookup for guests
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 0.8) // subtle border
                            )
                        }
                        
                        // Display "No events found" if applicable
                        if !eventRepository.isLoading && upcomingEvents.isEmpty && pastEvents.isEmpty && eventRepository.lastSyncErrorMessage == nil {
                            Text("No events found.")
                                .foregroundColor(.secondary)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .center)
                        }


                        // Sponsors section (Unchanged)
                        if !sponsors.isEmpty {
                            Text("Our Sponsors")
                                .font(.title2).bold()
                                .foregroundColor(.primary)
                                .padding(.horizontal)
                            TabView(selection: $currentSponsor) {
                                ForEach(Array(sponsors.enumerated()), id: \.offset) { idx, name in
                                    Image(name)
                                        .resizable()
                                        .renderingMode(.original)
                                        .scaledToFit()
                                        .frame(height: 60)
                                        .padding()
                                        .tag(idx)
                                }
                            }
                            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                            .frame(height: 100)
                            .onReceive(sponsorTimer) { _ in
                                withAnimation {
                                    currentSponsor = (currentSponsor + 1) % sponsors.count
                                }
                            }
                        }
                    }
                    .padding(.bottom)
                }
                // 3. Added .refreshable modifier for pull-to-refresh
                .refreshable {
                    print("[DashboardView] Refresh action triggered.")
                    await eventRepository.syncAllEvents(forceFullSync: true)
                }
            }
            .navigationBarHidden(true)
            .background(Color(.systemBackground))
        }
        // 4. Added .task modifier for initial data load and sync
        .task {
            if eventRepository.events.isEmpty {
                print("[DashboardView] Initial appearance: Loading events from Core Data then syncing.")
                await eventRepository.loadEventsFromCoreData(fetchLimit: 30) // Load from local store first with fetch limit
                Task.detached { [eventRepository] in
                    await eventRepository.syncAllEvents(forceFullSync: true) // True because Core Data was empty
                }
            } else {
                print("[DashboardView] Appeared with existing events, loading from Core Data then triggering background sync.")
                await eventRepository.loadEventsFromCoreData(fetchLimit: 30) // Still load a limited set for UI
                Task.detached { [eventRepository] in
                    await eventRepository.syncAllEvents(forceFullSync: false) // Delta sync
                }
            }
            print("[DashboardView] .task: Initial setup complete. Events count: \(eventRepository.events.count)")
        }
        // If your EventRepository needs the managedObjectContext explicitly passed,
        // and it's not already available via PersistenceController.shared within the repo.
        // .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
    }
} // end of file
