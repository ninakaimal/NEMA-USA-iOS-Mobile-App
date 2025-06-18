//
//  MyEventsView.swift
//  NEMA USA
//
//  Created by Nina on 6/18/25.
//

import SwiftUI
import SafariServices

struct MyEventsView: View {
    @StateObject private var viewModel = MyEventsViewModel()
    @AppStorage("jwtApiToken") private var jwtApiToken: String?

    var body: some View {
        // It checks the login token and shows either the `LoginView` or your events list.
        if jwtApiToken != nil {
            // --- LOGGED-IN VIEW ---
            ZStack {
                Color(.systemGroupedBackground).edgesIgnoringSafeArea(.all)

                if viewModel.isLoading {
                    ProgressView()
                } else if let errorMessage = viewModel.errorMessage {
                    ErrorStateView(message: errorMessage)
                } else {
                    if viewModel.upcomingEvents.isEmpty && viewModel.pastEvents.isEmpty {
                        EmptyStateView(
                            imageName: "doc.text.magnifyingglass",
                            title: "No Events Found",
                            message: "Your upcoming events and past registrations will appear here."
                        )
                    } else {
                        List {
                            if !viewModel.upcomingEvents.isEmpty {
                                Section(header: HeaderView(title: "Upcoming")) {
                                    ForEach(viewModel.upcomingEvents) { record in
                                        NavigationLink(destination: PurchaseDetailView(record: record)) {
                                            PurchaseRecordRowView(record: record)
                                        }
                                    }
                                }
                            }

                            if !viewModel.pastEvents.isEmpty {
                                Section(header: HeaderView(title: "Past")) {
                                    ForEach(viewModel.pastEvents) { record in
                                        NavigationLink(destination: PurchaseDetailView(record: record)) {
                                            PurchaseRecordRowView(record: record)
                                        }
                                    }
                                }
                            }
                        }
                        .listStyle(.insetGrouped)
                        .refreshable {
                            await viewModel.loadMyEvents()
                        }
                    }
                }
            }
            .navigationTitle("My Events")
            // This uses .onAppear to load data only when the view is actually shown on screen for the first time.
            .onAppear {
                if viewModel.upcomingEvents.isEmpty && viewModel.pastEvents.isEmpty {
                    Task {
                        await viewModel.loadMyEvents()
                    }
                }
            }
            // Listens for the login success notification and explicitly reloads the data, ensuring your events appear immediately after you log in.
            .onReceive(NotificationCenter.default.publisher(for: .didReceiveJWT)) { _ in
                Task {
                    await viewModel.loadMyEvents()
                }
            }

        } else {
            // --- LOGGED-OUT VIEW ---
            // Shows the LoginView directly when the user is not authenticated.
            // This is non-dismissible, as you requested.
            LoginView()
        }
    }
}


// MARK: - Subviews & Helpers
// All the code below this line is correct and does not need any changes.

private struct HeaderView: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.title2.bold())
            .foregroundColor(.primary)
            .textCase(nil)
            .padding(.bottom, 4)
    }
}

private struct EmptyStateView: View {
    let imageName: String
    let title: String
    let message: String
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: imageName)
                .font(.system(size: 50))
                .foregroundColor(.secondary)
            Text(title)
                .font(.title3.weight(.semibold))
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding()
    }
}

private struct ErrorStateView: View {
    let message: String
    var body: some View {
        EmptyStateView(
            imageName: "wifi.exclamationmark",
            title: "Loading Failed",
            message: message
        )
    }
}

private struct PurchaseRecordRowView: View {
    let record: PurchaseRecord
    
    var body: some View {
        HStack(spacing: 15) {
            Image(systemName: record.type == "Ticket Purchase" ? "ticket.fill" : "flag.fill")
                .font(.title2)
                .foregroundColor(.orange)
                .frame(width: 45, height: 45)
                .background(Color.orange.opacity(0.1))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                if let eventDate = record.eventDate {
                    Text(eventDate.formatted(.dateTime.month().day().year()))
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.orange)
                } else {
                    Text("Date: TBD")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                }
                
                Text(record.eventName)
                    .font(.headline)
                    .lineLimit(1)
                
                Text(record.title)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text(record.displayAmount)
                    .font(.headline.weight(.semibold))
                
                Text(record.status)
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(statusColor(for: record.status).opacity(0.15))
                    .foregroundColor(statusColor(for: record.status))
                    .cornerRadius(6)
            }
        }
        .padding(.vertical, 8)
    }
    
    private func statusColor(for status: String) -> Color {
        switch status.lowercased() {
        case "paid", "registration success":
            return .green
        case "wait list", "approved, pending payment":
            return .orange
        case "registration withdrawn":
            return .red
        default:
            return .gray
        }
    }
}

// MARK: - Detail View and its Helpers

struct PurchaseDetailView: View {
    let record: PurchaseRecord
    @StateObject private var viewModel = PurchaseDetailViewModel()
    @State private var pdfURLToOpen: URL?
    
    var body: some View {
        Form {
            if viewModel.isLoading {
                HStack { Spacer(); ProgressView(); Spacer() }
                    .listRowBackground(Color.clear)
            } else if let ticketInfo = viewModel.ticketDetail {
                TicketDetailSection(ticketInfo: ticketInfo, eventName: record.eventName, pdfURLToOpen: $pdfURLToOpen)
            } else if let programInfo = viewModel.programDetail {
                ProgramDetailSection(programInfo: programInfo,eventName: record.eventName)
            } else if let error = viewModel.errorMessage {
                Text(error).foregroundColor(.red)
            }
        }
        .navigationTitle("Purchase Details")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadDetails(for: record)
        }
        .sheet(item: $pdfURLToOpen) { url in
            SafariView(url: url)
        }
    }
}

private struct TicketDetailSection: View {
    let ticketInfo: TicketPurchaseDetailResponse
    let eventName: String
    @Binding var pdfURLToOpen: URL?
    
    var body: some View {
        Section(header: Text("Event & Ticket Details")) {
            InfoRow(label: "Event", value: ticketInfo.purchase.details.first?.ticketType.event?.title ?? eventName)
            InfoRow(label: "Purchaser", value: ticketInfo.purchase.name)
            InfoRow(label: "Email", value: ticketInfo.purchase.email)
            InfoRow(label: "Phone", value: ticketInfo.purchase.phone)
            if let panthi = ticketInfo.purchase.panthi {
                InfoRow(label: "Time Slot", value: panthi.name)
            }
        }
        
        Section(header: Text("Items Purchased")) {
            ForEach(ticketInfo.purchase.details) { item in
                HStack {
                    Text("\(item.no) x \(item.ticketType.typeName)")
                    Spacer()
                    Text("$\(item.amount) each")
                        .foregroundColor(.secondary)
                }
            }
            HStack {
                Text("Total").fontWeight(.bold)
                Spacer()
                Text("$\(ticketInfo.purchase.totalAmount)")
                    .fontWeight(.bold)
            }
        }
        
        if let urlString = ticketInfo.pdfUrl, let url = URL(string: urlString) {
            Section {
                Button(action: { pdfURLToOpen = url }) {
                    HStack {
                        Spacer()
                        Image(systemName: "doc.text.fill")
                        Text("View E-Ticket PDF")
                        Spacer()
                    }
                }
                .tint(.orange)
            }
        }
    }
}

private struct ProgramDetailSection: View {
    let programInfo: Participant
    let eventName: String
    
    var body: some View {
        Section(header: Text("Registration Details")) {
            InfoRow(label: "Event", value: programInfo.category.programs.event?.title ?? eventName)
            InfoRow(label: "Program", value: programInfo.category.programs.name)
            InfoRow(label: "Category", value: programInfo.category.age.name)
            InfoRow(label: "Fee", value: "$\(String(format: "%.2f", programInfo.amount))")
        }
        
        Section(header: Text("Participants")) {
            ForEach(programInfo.details) { detail in
                Text(detail.name)
            }
        }
        
        if let comments = programInfo.comments, !comments.isEmpty {
            Section(header: Text("Comments")) {
                Text(comments)
            }
        }
    }
}

private struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }
}

private struct SafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        return SFSafariViewController(url: url)
    }
    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
