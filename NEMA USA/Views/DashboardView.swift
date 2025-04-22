// DashboardView.swift
// NEMA USA
// Created by Nina on 4/16/25.

import SwiftUI

struct DashboardView: View {
    @StateObject private var loader = EventLoader()
    @State private var searchQuery = ""
    @State private var selectedCategory: String = "All"
    @FocusState private var isSearchFocused: Bool

    let sponsors = ["sponsor1", "sponsor2", "sponsor3", "sponsor4", "sponsor5"]
    @State private var currentSponsor = 0
    private let sponsorTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var categories: [String] {
        let cats = loader.events.map(\.category)
        return ["All"] + Set(cats).sorted()
    }

    var filteredEvents: [Event] {
        loader.events.filter { ev in
            let matchesSearch = searchQuery.isEmpty
                || ev.title.localizedCaseInsensitiveContains(searchQuery)
                || ev.description.localizedCaseInsensitiveContains(searchQuery)
                || ev.location.localizedCaseInsensitiveContains(searchQuery)
            let matchesCat = selectedCategory == "All" || ev.category == selectedCategory
            return matchesSearch && matchesCat
        }
    }

    var upcomingEvents: [Event] {
        filteredEvents
            .filter { $0.date.map { $0 >= Date() } ?? $0.isTBD }
            .sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
    }

    var pastEvents: [Event] {
        filteredEvents
            .filter { $0.date.map { $0 < Date() } ?? false }
            .sorted { ($0.date ?? Date()) > ($1.date ?? Date()) }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                BannerView()
                Spacer().frame(height: 16)

                // Search bar
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

                // Category selector
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(categories, id: \.self) { cat in
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
                        if !upcomingEvents.isEmpty {
                            Text("Upcoming Events")
                                .font(.title2).bold()
                                .foregroundColor(.primary)
                                .padding(.horizontal)
                            LazyVStack(spacing: 16) {
                                ForEach(upcomingEvents) { ev in
                                    NavigationLink(destination: EventDetailView(event: ev)) {
                                        EventCard(event: ev)
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }

                        if !pastEvents.isEmpty {
                            Text("Past Events")
                                .font(.title2).bold()
                                .foregroundColor(.primary)
                                .padding(.horizontal)
                            LazyVStack(spacing: 16) {
                                ForEach(pastEvents) { ev in
                                    NavigationLink(destination: EventDetailView(event: ev)) {
                                        EventCard(event: ev)
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }

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
            }
            .navigationBarHidden(true)
            .background(Color(.systemBackground))
            // ← Removed .accentColor(.primary) so EventDetail’s white back‑chevron can show
        }
    }
}
