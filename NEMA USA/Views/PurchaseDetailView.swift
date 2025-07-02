//
//  PurchaseDetailView.swift
//  NEMA USA
//
//  Created by Nina Kaimal on 6/27/25.
//
import SwiftUI

struct PurchaseDetailView: View {
    let record: PurchaseRecord
    @StateObject private var viewModel = PurchaseDetailViewModel()
    @Environment(\.presentationMode) private var presentationMode
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    if viewModel.isLoading {
                        ProgressView("Loading details...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(.top, 100)
                    } else if let errorMessage = viewModel.errorMessage {
                        ErrorStateView(message: errorMessage) {
                            Task {
                                await viewModel.loadDetails(for: record)
                            }
                        }
                    } else {
                        VStack(spacing: 20) {
                            // Header Section
                            HeaderSection(record: record)
                            
                            if record.type == "Ticket Purchase" {
                                TicketDetailsSection(ticketDetail: viewModel.ticketDetail)
                            } else {
                                ProgramDetailsSection(programDetail: viewModel.programDetail)
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Purchase Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
        .task {
            await viewModel.loadDetails(for: record)
        }
    }
}

struct HeaderSection: View {
    let record: PurchaseRecord
    
    private var eventDateText: String {
        if let eventDate = record.eventDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .full
            return formatter.string(from: eventDate)
        } else {
            return "Date to be announced"
        }
    }
    
    private var purchaseDateText: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: record.purchaseDate)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Event Name
            Text(record.eventName)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            
            // Type and Status
            HStack {
                Label(record.type, systemImage: record.type == "Ticket Purchase" ? "ticket" : "person.2")
                    .font(.subheadline)
                    .foregroundColor(.orange)
                
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
            
            Divider()
            
            // Event Date
            VStack(alignment: .leading, spacing: 8) {
                Label("Event Date", systemImage: "calendar")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text(eventDateText)
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            
            // Purchase Date
            VStack(alignment: .leading, spacing: 8) {
                Label("Purchase Date", systemImage: "clock")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text(purchaseDateText)
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            
            // Amount
            VStack(alignment: .leading, spacing: 8) {
                Label("Total Amount", systemImage: "dollarsign.circle")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text(record.displayAmount)
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.green)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
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
}

struct TicketDetailsSection: View {
    let ticketDetail: TicketPurchaseDetailResponse?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Ticket Details")
                .font(.headline)
                .foregroundColor(.primary)
            
            if let detail = ticketDetail {
                VStack(alignment: .leading, spacing: 12) {
                    // Contact Information
                    GroupBox("Contact Information") {
                        VStack(alignment: .leading, spacing: 8) {
                            DetailRow(label: "Name", value: detail.purchase.name)
                            DetailRow(label: "Email", value: detail.purchase.email)
                            DetailRow(label: "Phone", value: detail.purchase.phone)
                        }
                    }
                    
                    // Ticket Types
                    GroupBox("Tickets Purchased") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(detail.purchase.details.indices, id: \.self) { index in
                                let ticketDetail = detail.purchase.details[index]
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(ticketDetail.ticketType.typeName)
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                        Text("\(ticketDetail.no) ticket\(ticketDetail.no > 1 ? "s" : "")")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    Text("$\(String(format: "%.2f", ticketDetail.amount))")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                }
                                
                                if index < detail.purchase.details.count - 1 {
                                    Divider()
                                }
                            }
                        }
                    }
                    
                    // Panthi Information (if applicable)
                    if let panthi = detail.purchase.panthi {
                        GroupBox("Seating Assignment") {
                            DetailRow(label: "Panthi", value: panthi.title)
                        }
                    }
                    
                    // PDF Download (if available)
                    if let pdfUrl = detail.pdfUrl {
                        Button(action: {
                            if let url = URL(string: pdfUrl) {
                                UIApplication.shared.open(url)
                            }
                        }) {
                            HStack {
                                Image(systemName: "doc.fill")
                                Text("Download Ticket PDF")
                                Spacer()
                                Image(systemName: "arrow.down.circle")
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.orange)
                            .cornerRadius(10)
                        }
                    }
                }
            } else {
                Text("Loading ticket details...")
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

struct ProgramDetailsSection: View {
    let programDetail: Participant?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Registration Details")
                .font(.headline)
                .foregroundColor(.primary)
            
            if let detail = programDetail {
                VStack(alignment: .leading, spacing: 12) {
                    // Program Information
                    GroupBox("Program Information") {
                        VStack(alignment: .leading, spacing: 8) {
                            DetailRow(label: "Program", value: detail.category.programs.name)
                            DetailRow(label: "Category", value: detail.category.age.name)
                            if let comments = detail.comments, !comments.isEmpty {
                                DetailRow(label: "Comments", value: comments)
                            }
                        }
                    }
                    
                    // Participants
                    GroupBox("Registered Participants") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(detail.details.indices, id: \.self) { index in
                                let participant = detail.details[index]
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(participant.name)
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                        if let age = participant.age {
                                            Text("Age: \(age)")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    Spacer()
                                }
                                
                                if index < detail.details.count - 1 {
                                    Divider()
                                }
                            }
                        }
                    }
                }
            } else {
                Text("Loading registration details...")
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

struct DetailRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
                .multilineTextAlignment(.trailing)
        }
    }
}

struct ErrorStateView: View {
    let message: String
    let retryAction: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundColor(.orange)
            
            Text("Error Loading Details")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)
            
            Button("Try Again", action: retryAction)
                .font(.headline)
                .foregroundColor(.white)
                .padding()
                .background(Color.orange)
                .cornerRadius(10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

#Preview {
    let sampleRecord = PurchaseRecord(
        recordId: "ticket-123",
        type: "Ticket Purchase",
        purchaseDate: Date(),
        eventDate: Calendar.current.date(byAdding: .day, value: 30, to: Date()),
        eventName: "NEMA Onam 2025",
        title: "2 Tickets",
        displayAmount: "$50.00",
        status: "Paid",
        detailId: 123
    )
    
    PurchaseDetailView(record: sampleRecord)
}
