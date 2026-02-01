//
//  MyEventsView.swift
//  NEMA USA
//
//  Created by Nina on 6/18/25.
//

import SwiftUI

struct MyEventsView: View {
    @StateObject private var viewModel = MyEventsViewModel()
    @State private var selectedRecord: PurchaseRecord?
    @State private var hasAppeared = false
    
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
                                LazyVStack(spacing: 16) {
                                    ForEach(viewModel.purchaseRecords) { record in
                                        MyEventCard(record: record)
                                            .onTapGesture {
                                                guard selectedRecord == nil else { return }
                                                selectedRecord = record
                                            }
                                    }
                                }
                                .padding(.horizontal)
                                
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
