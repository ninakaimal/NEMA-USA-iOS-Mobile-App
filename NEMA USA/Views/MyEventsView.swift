//
//  MyEventsView.swift
//  NEMA USA
//
//  Created by Nina on 6/18/25.
//

import SwiftUI

struct MyEventsView: View {
    @StateObject private var viewModel = MyEventsViewModel()
    @StateObject private var eventRepository = EventRepository()
    @State private var selectedRecord: PurchaseRecord?
    @State private var hasAppeared = false
    @State private var searchQuery: String = ""
    @State private var selectedCategory: String = "All"
    @FocusState private var isSearchFocused: Bool
    
    var body: some View {
        NavigationView {
            ZStack(alignment: .top) {
                Color.orange
                    .ignoresSafeArea(edges: .top)
                    .frame(height: 56)

                // Check for authentication first - if no token, show login like AccountView
                if DatabaseManager.shared.jwtApiToken == nil {
                    LoginView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            Spacer().frame(height: 16)
                            
                            if !viewModel.purchaseRecords.isEmpty {
                                searchBar
                                categoryChips
                            }
                            
                            if viewModel.isLoading && viewModel.purchaseRecords.isEmpty {
                                ProgressView("Loading your events...")
                                    .padding()
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                
                            } else if let errorMessage = viewModel.errorMessage, viewModel.purchaseRecords.isEmpty {
                                if errorMessage.lowercased().contains("authentication") || errorMessage.lowercased().contains("expired") {
                                    LoginView()
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                } else {
                                    VStack(spacing: 16) {
                                        Image(systemName: "exclamationmark.triangle")
                                            .font(.system(size: 50))
                                            .foregroundColor(.orange)
                                        
                                        Text("Unable to Load Events")
                                            .font(.title2)
                                            .fontWeight(.semibold)
                                        
                                        Text(errorMessage)
                                            .multilineTextAlignment(.center)
                                            .foregroundColor(.secondary)
                                            .padding(.horizontal)
                                        
                                        Button("Try Again") {
                                            viewModel.clearError()
                                            Task {
                                                await viewModel.loadMyEvents()
                                            }
                                        }
                                        .font(.headline)
                                        .foregroundColor(.white)
                                        .padding()
                                        .background(Color.orange)
                                        .cornerRadius(10)
                                    }
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                }
                                
                            } else if viewModel.purchaseRecords.isEmpty && !viewModel.isLoading {
                                VStack(spacing: 16) {
                                    Image(systemName: "calendar.badge.exclamationmark")
                                        .font(.system(size: 50))
                                        .foregroundColor(.gray)
                                    
                                    Text("No Events Found")
                                        .font(.title2)
                                        .fontWeight(.semibold)
                                    
                                    Text("You haven't registered for any events or purchased any tickets yet.")
                                        .multilineTextAlignment(.center)
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal)
                                    
                                    Button("Browse Events") {
                                        // Navigate to events list
                                    }
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .padding()
                                    .background(Color.orange)
                                    .cornerRadius(10)
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                
                            } else {
                                if filteredRecords.isEmpty {
                                    VStack(spacing: 16) {
                                        Image(systemName: "line.3.horizontal.decrease.circle")
                                            .font(.system(size: 48))
                                            .foregroundColor(.gray)
                                        Text("No matching events")
                                            .font(.title3)
                                            .fontWeight(.semibold)
                                        Text(hasActiveFilters ? "Try adjusting your search or category filters." : "No events match your filters right now.")
                                            .multilineTextAlignment(.center)
                                            .foregroundColor(.secondary)
                                            .padding(.horizontal)
                                        if hasActiveFilters {
                                            Button("Clear Filters") {
                                                withAnimation {
                                                    searchQuery = ""
                                                    selectedCategory = "All"
                                                }
                                            }
                                            .font(.headline)
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 24)
                                            .padding(.vertical, 10)
                                            .background(Color.orange)
                                            .cornerRadius(12)
                                        }
                                    }
                                    .padding()
                                } else {
                                    LazyVStack(spacing: 16) {
                                        ForEach(filteredRecords) { record in
                                            MyEventCard(record: record)
                                                .onTapGesture {
                                                    guard selectedRecord == nil else { return }
                                                    selectedRecord = record
                                                }
                                        }
                                    }
                                    .padding(.horizontal)
                                }
                                
                                if viewModel.isLoading && !viewModel.purchaseRecords.isEmpty {
                                    ProgressView("Refreshing...")
                                        .padding()
                                }
                            }
                        }
                        .padding(.bottom)
                        .background(Color(.systemBackground))
                    }
                    .refreshable {
                        await viewModel.refreshMyEvents()
                    }
                }
            }
            .navigationTitle("My Events")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            // Always check auth status when View appears
            if DatabaseManager.shared.jwtApiToken == nil {
                viewModel.clearData()
                hasAppeared = false
            } else if !hasAppeared {
                hasAppeared = true
                Task {
                    await viewModel.loadMyEvents()
                }
            }
        }
        .sheet(item: $selectedRecord) { record in
            PurchaseDetailView(record: record)
        }
        .onReceive(NotificationCenter.default.publisher(for: .didReceiveJWT)) { _ in
            Task {
                await viewModel.loadMyEvents()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .didSessionExpire)) { _ in
            // When user logs out or session expires, clear the data and show login
            viewModel.clearData()
            hasAppeared = false
        }
        .task {
            await eventRepository.loadEventsFromCoreData(fetchLimit: 100)
        }
        .onChange(of: viewModel.purchaseRecords) { _ in
            if !availableCategories.contains(selectedCategory) {
                selectedCategory = "All"
            }
        }
        .onChange(of: eventRepository.events) { _ in
            if !availableCategories.contains(selectedCategory) {
                selectedCategory = "All"
            }
        }
    }

    private var availableCategories: [String] {
        let derived = viewModel.purchaseRecords
            .map { categoryLabel(for: $0) }
            .filter { !$0.isEmpty }
        let unique = Array(Set(derived)).sorted()
        return ["All"] + unique
    }
    
    private var filteredRecords: [PurchaseRecord] {
        viewModel.purchaseRecords.filter { record in
            matchesSearch(record) && matchesCategory(record)
        }
    }
    
    private var hasActiveFilters: Bool {
        !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedCategory != "All"
    }
    
    private var searchBar: some View {
        HStack {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.gray)
                TextField("Search my events…", text: $searchQuery)
                    .focused($isSearchFocused)
                    .disableAutocorrection(true)
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
        .padding(.bottom, 4)
    }
    
    private var categoryChips: some View {
        Group {
            if availableCategories.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(availableCategories, id: \.self) { cat in
                            Button(cat) {
                                withAnimation { selectedCategory = cat }
                            }
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
                .padding(.bottom, 8)
            }
        }
    }
    
    private func matchesSearch(_ record: PurchaseRecord) -> Bool {
        let trimmedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return true }
        return record.eventName.localizedCaseInsensitiveContains(trimmedQuery) ||
            record.title.localizedCaseInsensitiveContains(trimmedQuery) ||
            (record.subtitle?.localizedCaseInsensitiveContains(trimmedQuery) ?? false) ||
            record.status.localizedCaseInsensitiveContains(trimmedQuery) ||
            record.type.localizedCaseInsensitiveContains(trimmedQuery)
    }
    
    private func matchesCategory(_ record: PurchaseRecord) -> Bool {
        selectedCategory == "All" || categoryLabel(for: record) == selectedCategory
    }
    
    private func categoryLabel(for record: PurchaseRecord) -> String {
        if let eventId = record.eventId,
           let eventCategory = eventRepository.events.first(where: { $0.id == eventId })?.categoryName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !eventCategory.isEmpty {
            return eventCategory
        }
        let typeLower = record.type.lowercased()
        if typeLower.contains("ticket") { return "Tickets" }
        if typeLower.contains("program") { return "Programs" }
        return record.type.isEmpty ? "Other" : record.type
    }
}

// MyEventCard remains the same
struct MyEventCard: View {
    let record: PurchaseRecord
    
    private var eventDateText: String {
        if let eventDate = record.eventDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return formatter.string(from: eventDate)
        } else {
            return "Date TBD"
        }
    }
    
    private var purchaseDateText: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return "Purchased \(formatter.string(from: record.purchaseDate))"
    }
    
    private var statusColor: Color {
        switch record.status.lowercased() {
        case "paid":
            return .green
        case "approved":
            return Color.green.opacity(0.6)
        case "success", "registered":
            return .blue
        case "wait_list", "wait list", "waiting_list", "waiting list", "waitlist":
            return .orange
        case "pending":
            return .yellow
        case "rejected", "failed":
            return .red
        case "cancelled", "withdrawn":
            return .gray
        default:
            return .gray
        }
    }
    
    private var displayStatus: String {
        switch record.status.lowercased() {
        case "success":
            return "Registered"
        case "paid":
            return "Purchased"
        case "wait_list", "wait list", "waiting_list", "waiting list", "waitlist":
            return "Waitlisted"
        case "approved":
            return "Approved"
        case "rejected":
            return "Rejected"
        case "failed":
            return "Failed"
        case "cancelled", "withdrawn":
            return "Withdrawn"
        default:
            return record.status
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with type and status
            HStack {
                Text(record.type)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(8)
                
                Spacer()
                
                Text(displayStatus)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusColor)
                    .cornerRadius(8)
            }
            
            // CONDITIONAL DISPLAY BASED ON TYPE
            if record.type == "Program Registration" {
                // NEW FORMAT FOR PROGRAMS
                // 1. Program name as title
                Text(record.title)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                
                // 2. Participant info as subtitle
                if let subtitle = record.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                // 3. Event name as third line
                Text(record.eventName)
                    .font(.caption)
                    .foregroundColor(.gray)
                    .lineLimit(1)
            } else {
                // ORIGINAL FORMAT FOR TICKETS
                // 1. Event name as title
                Text(record.eventName)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                
                // 2. Ticket count as subtitle
                Text(record.title)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            // Date and amount (same for both types)
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "calendar")
                            .foregroundColor(.orange)
                            .font(.caption)
                        Text(eventDateText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Image(systemName: "clock")
                            .foregroundColor(.gray)
                            .font(.caption)
                        Text(purchaseDateText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // Show amount if it exists
                if let amount = record.displayAmount {
                    Text(amount)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
}

#Preview {
    MyEventsView()
}
