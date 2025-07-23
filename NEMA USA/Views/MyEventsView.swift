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
        VStack {
            if viewModel.isLoading && viewModel.purchaseRecords.isEmpty {
                // Loading state for initial load only when no cached data
                VStack(spacing: 20) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("Loading your events...")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
            } else if let errorMessage = viewModel.errorMessage, viewModel.purchaseRecords.isEmpty {
                // Error state - only show if we have no cached data
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
                
            } else if viewModel.purchaseRecords.isEmpty && !viewModel.isLoading {
                // Empty state - only show if not loading and truly empty
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
                        // Navigate to events list - you may need to implement this
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.orange)
                    .cornerRadius(10)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
            } else {
                // Main content - show cached data even while loading fresh data
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(viewModel.purchaseRecords) { record in
                            MyEventCard(record: record)
                                .onTapGesture {
                                    // Prevent rapid taps
                                    guard selectedRecord == nil else { return }
                                    selectedRecord = record
                                }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top)
                }
                .refreshable {
                    await viewModel.refreshMyEvents()
                }
                .overlay(
                    // Show a subtle loading indicator when refreshing
                    Group {
                        if viewModel.isLoading && !viewModel.purchaseRecords.isEmpty {
                            VStack {
                                HStack {
                                    Spacer()
                                    ProgressView()
                                        .scaleEffect(0.8)
                                        .padding(.trailing)
                                        .padding(.top, 8)
                                }
                                Spacer()
                            }
                        }
                    }
                )
            }
        }
        .navigationTitle("My Events")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            // Only load on first appearance to avoid duplicate requests
            if !hasAppeared {
                hasAppeared = true
                Task {
                    await viewModel.loadMyEvents()
                }
            }
        }
        .sheet(item: $selectedRecord) { record in
            PurchaseDetailView(record: record)
        }
        .fullScreenCover(isPresented: $viewModel.shouldShowLogin) {
            LoginView()
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
        case "paid", "success":
            return .green
        case "wait_list", "wait list":
            return .orange
        case "pending":
            return .yellow
        default:
            return .gray
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
                
                Text(record.status)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusColor)
                    .cornerRadius(8)
            }
            
            // Event name
            Text(record.eventName)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
                .lineLimit(2)
            
            // Title (ticket count or program name)
            Text(record.title)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(1)
            
            // Date and amount
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
                
                Text(record.displayAmount)
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
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
