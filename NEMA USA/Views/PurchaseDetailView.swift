//
//  PurchaseDetailView.swift
//  NEMA USA
//
//  Created by Nina Kaimal on 6/27/25.
//

import SwiftUI

struct PurchaseDetailView: View {
    let record: PurchaseRecord
    @StateObject private var viewModel: PurchaseDetailViewModel
    @Environment(\.presentationMode) private var presentationMode

    @State private var showWithdrawConfirmation = false
    @State private var showWithdrawSuccess = false
    @State private var participantNamesForWithdraw = ""
    @State private var programNameForWithdraw = ""
    private let eventIsInPast: Bool

    init(record: PurchaseRecord) {
        self.record = record
        _viewModel = StateObject(wrappedValue: PurchaseDetailViewModel())
        if let eventDate = record.eventDate {
            let startOfToday = Calendar.current.startOfDay(for: Date())
            self.eventIsInPast = eventDate < startOfToday
        } else {
            self.eventIsInPast = false
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Hero Header Section
                HeroHeaderSection(record: record)
                    .padding(.top, 20)
                    
                    if viewModel.isLoading {
                        LoadingStateView()
                    } else if let errorMessage = viewModel.errorMessage {
                        ErrorStateView(message: errorMessage) {
                            Task { await viewModel.loadDetails(for: record) }
                        }
                    } else {
                        // Details Section
                        if record.type == "Ticket Purchase" {
                            TicketDetailsSection(ticketDetail: viewModel.ticketDetail)
                        } else {
                            ProgramDetailsSection(programDetail: viewModel.programDetail)

                            // Withdrawal Button - Only show for eligible statuses
                            if let detail = viewModel.programDetail,
                               shouldShowWithdrawButton(for: detail) {

                                Button(action: {
                                    // Prepare confirmation message data
                                    participantNamesForWithdraw = detail.details.map { $0.name }.joined(separator: ", ")
                                    programNameForWithdraw = detail.category.programs.name
                                    showWithdrawConfirmation = true
                                }) {
                                    HStack(spacing: 12) {
                                        if viewModel.isWithdrawing {
                                            ProgressView()
                                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                                .scaleEffect(0.9)
                                        } else {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.headline)
                                        }

                                        Text(viewModel.isWithdrawing ? "Withdrawing..." : "Withdraw Registration")
                                            .font(.headline)
                                            .fontWeight(.semibold)

                                        Spacer()
                                    }
                                    .foregroundColor(.white)
                                    .padding(16)
                                    .background(viewModel.isWithdrawing ? Color.gray : Color.orange)
                                    .cornerRadius(16)
                                    .shadow(color: (viewModel.isWithdrawing ? Color.gray : Color.orange).opacity(0.3), radius: 8, x: 0, y: 4)
                                }
                                .buttonStyle(PlainButtonStyle())
                                .disabled(viewModel.isWithdrawing)
                            }
                        }
                    }

                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 20)
            }
        .navigationTitle("Purchase Details")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(false)
        .task {
            await viewModel.loadDetails(for: record)
        }
        .alert("Confirm Withdrawal", isPresented: $showWithdrawConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Withdraw", role: .destructive) {
                Task {
                    await handleWithdraw()
                }
            }
        } message: {
            Text("Are you sure you want to withdraw \(participantNamesForWithdraw) from \(programNameForWithdraw)?")
        }
        .alert("Withdrawal Successful", isPresented: $showWithdrawSuccess) {
            Button("OK", role: .cancel) {
                presentationMode.wrappedValue.dismiss()
            }
        } message: {
            if let successMsg = viewModel.withdrawSuccessMessage {
                Text(successMsg)
            } else {
                Text("\(participantNamesForWithdraw)'s \(programNameForWithdraw) registration has been withdrawn successfully.")
            }
        }
        .alert("Withdrawal Failed", isPresented: Binding(
            get: { viewModel.withdrawErrorMessage != nil },
            set: { if !$0 { viewModel.withdrawErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            if let error = viewModel.withdrawErrorMessage {
                Text(error)
            }
        }
    }

    private func handleWithdraw() async {
        guard let detail = viewModel.programDetail else { return }

        await viewModel.withdrawRegistration(participantId: detail.id)

        if viewModel.withdrawSuccess {
            // Set success message from server or use default
            if viewModel.withdrawSuccessMessage == nil {
                viewModel.withdrawSuccessMessage = "\(participantNamesForWithdraw)'s \(programNameForWithdraw) registration has been withdrawn successfully."
            }
            showWithdrawSuccess = true
        }
    }

    private func shouldShowWithdrawButton(for detail: Participant) -> Bool {
        guard !["cancelled", "withdrawn", "rejected", "failed"].contains(detail.regStatus.lowercased()) else {
            return false
        }
        return !eventIsInPast
    }
}

// MARK: - Hero Header Section
struct HeroHeaderSection: View {
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
        VStack(spacing: 20) {
            // Status Badge
            HStack {
                Spacer()
                StatusBadge(status: record.status)
            }
            
            VStack(spacing: 16) {
                // Event Name
                Text(record.eventName)
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                
                // Type Badge
                HStack(spacing: 8) {
                    Image(systemName: record.type == "Ticket Purchase" ? "ticket.fill" : "person.2.fill")
                        .foregroundColor(.orange)
                    Text(record.type)
                        .fontWeight(.medium)
                }
                .font(.subheadline)
                .foregroundColor(.orange)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(20)
                
                // Payment reminder for Approved status
                if record.status.lowercased() == "approved" {
                    Text("Please complete the payment within 24 hours to confirm your ticket by logging into www.nemausa.org and visiting the MyAccount/Tickets page.")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .background(Color.orange.opacity(0.05))
                        .cornerRadius(10)
                }
                
                // Amount - Prominent display
                VStack(spacing: 4) {
                    Text("Total Amount")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if let amount = record.displayAmount {
                        Text(amount)
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                    } else {
                        Text("Free registration")
                            .font(.title2)
                            .fontWeight(.medium)
                            .foregroundColor(.green)
                    }
                }
            }
            
            // Quick Info Cards
            HStack(spacing: 12) {
                QuickInfoCard(
                    icon: "calendar",
                    title: "Event Date",
                    value: eventDateText
                )
                
                QuickInfoCard(
                    icon: "clock",
                    title: "Purchased",
                    value: purchaseDateText
                )
            }
        }
        .padding(24)
        .background(Color(.systemBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.orange, lineWidth: 2)
        )
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

// MARK: - Quick Info Card
struct QuickInfoCard: View {
    let icon: String
    let title: String
    let value: String
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.orange)
            
            VStack(spacing: 2) {
                Text(title)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .bold()
                
                Text(value)
                    .font(.caption)
                    .bold()
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

// MARK: - Status Badge
struct StatusBadge: View {
    let status: String
    
    private var displayStatus: String {
        switch status.lowercased() {
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
            return status
        }
    }
    
    private var statusConfig: (color: Color, icon: String) {
        switch status.lowercased() {
        case "paid":
            return (.green, "checkmark.circle.fill")
        case "approved":
            return (Color.green.opacity(0.6), "checkmark.circle.fill")  // Light green
        case "success", "registered":
            return (.blue, "checkmark.circle.fill")
        case "wait_list", "wait list", "waiting_list", "waiting list", "waitlist":
            return (.orange, "clock.fill")
        case "pending":
            return (.yellow, "hourglass")
        case "rejected", "failed":
            return (.red, "xmark.circle.fill")
        case "cancelled", "withdrawn":
            return (.gray, "minus.circle.fill")
        default:
            return (.gray, "questionmark.circle.fill")
        }
    }
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: statusConfig.icon)
                .font(.caption)
            Text(displayStatus)
                .font(.caption)
                .fontWeight(.semibold)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(statusConfig.color)
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 2)
    }
}

// MARK: - Enhanced Ticket Details Section
struct TicketDetailsSection: View {
    let ticketDetail: TicketPurchaseDetailResponse?
    
    var body: some View {
        VStack(spacing: 20) {
            SectionHeader(title: "Ticket Details", icon: "ticket.fill")
            
            if let detail = ticketDetail {
                VStack(spacing: 16) {
                    // Ticket Types - Moved up first
                    ModernCard {
                        CardHeader(title: "Tickets Purchased", icon: "ticket")
                        
                        VStack(spacing: 12) {
                            // Filter ticket types based on membership status
                            let isMember = AccountViewHelper.isActiveMember()
                            let visibleDetails = detail.purchase.details.filter {
                                let mirror = Mirror(reflecting: $0.ticketType)
                                var isExclusiveFlag: Bool?
                                var typeName: String?
                                
                                for child in mirror.children {
                                    guard let label = child.label?.lowercased() else { continue }
                                    if (label == "is_ticket_type_member_exclusive" || label == "istickettypememberexclusive"),
                                       let val = child.value as? Bool {
                                        isExclusiveFlag = val
                                    }
                                    if (label == "type_name" || label == "typename" || label == "type"),
                                       let name = child.value as? String {
                                        typeName = name
                                    }
                                }

                                // Fallback inference from the type name if the flag is missing/incorrect
                                let inferredExclusive: Bool = {
                                    guard let name = typeName?.lowercased() else { return false }
                                    let hasMember = name.contains("member")
                                    let hasNonMember = name.contains("non-member") || name.contains("non member") || name.contains("nonmember")
                                    return hasMember && !hasNonMember
                                }()

                                // Final decision: explicit flag wins if true; otherwise use inference
                                let isExclusive = (isExclusiveFlag ?? false) || inferredExclusive

                                return isMember || !isExclusive
                            }
                            
                            ForEach(visibleDetails.indices, id: \.self) { index in
                                let ticketDetail = visibleDetails[index]
                                TicketRow(ticketDetail: ticketDetail)
                                if index < visibleDetails.count - 1 {
                                    DividerLine()
                                }
                            }
                        }
                    }
                    
                    // Contact Information - Moved below tickets
                    ModernCard {
                        CardHeader(title: "Contact Information", icon: "person.fill")
                        
                        VStack(spacing: 12) {
                            InfoRow(icon: "person", label: "Name", value: detail.purchase.name)
                            InfoRow(icon: "envelope", label: "Email", value: detail.purchase.email)
                            InfoRow(icon: "phone", label: "Phone", value: detail.purchase.phone)
                        }
                    }
                    
                    // Panthi Information (if applicable)
                    if let panthi = detail.purchase.panthi {
                        ModernCard {
                            CardHeader(title: "Seating Assignment", icon: "map")
                            InfoRow(icon: "location", label: "Panthi", value: panthi.title)
                        }
                    }
                    
                    // PDF Download (if available)
                    if let pdfUrl = detail.pdfUrl {
                        DownloadButton(pdfUrl: pdfUrl)
                    }
                }
            } else {
                LoadingCard(message: "Loading ticket details...")
            }
        }
    }
}

// MARK: - Enhanced Program Details Section
struct ProgramDetailsSection: View {
    let programDetail: Participant?
    
    var body: some View {
        VStack(spacing: 20) {
            SectionHeader(title: "Registration Details", icon: "person.2.fill")
            
            if let detail = programDetail {
                VStack(spacing: 16) {
                    // Program Information
                    ModernCard {
                        CardHeader(title: "Program Information", icon: "flag.fill")
                        
                        VStack(spacing: 12) {
                            InfoRow(icon: "flag", label: "Program", value: detail.category.programs.name)
                            InfoRow(icon: "tag", label: "Category", value: detail.category.age.name)
                            if let comments = detail.comments, !comments.isEmpty {
                                InfoRow(icon: "text.bubble", label: "Comments", value: comments)
                            }
                        }
                    }
                    
                    // Participants
                    ModernCard {
                        CardHeader(title: "Registered Participants", icon: "person.3")
                        
                        VStack(spacing: 12) {
                            ForEach(detail.details.indices, id: \.self) { index in
                                let participant = detail.details[index]
                                ParticipantRow(participant: participant)
                                
                                if index < detail.details.count - 1 {
                                    DividerLine()
                                }
                            }
                        }
                    }
                }
            } else {
                LoadingCard(message: "Loading registration details...")
            }
        }
    }
}

// MARK: - Reusable Components

struct SectionHeader: View {
    let title: String
    let icon: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.orange)
            
            Text(title)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            
            Spacer()
        }
    }
}

struct ModernCard<Content: View>: View {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            content
        }
        .padding(20)
        .background(Color(.systemBackground))
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 4)
    }
}

struct CardHeader: View {
    let title: String
    let icon: String
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundColor(.orange)
            
            Text(title)
                .font(.headline)
                .bold()
                .foregroundColor(.primary)
            
            Spacer()
        }
        .padding(.bottom, 4)
    }
}

struct InfoRow: View {
    let icon: String
    let label: String
    let value: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundColor(.orange)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .bold()
                
                Text(value)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .bold()
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

struct TicketRow: View {
    let ticketDetail: TicketPurchaseDetail
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "ticket")
                .font(.subheadline)
                .foregroundColor(.orange)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(ticketDetail.ticketType.typeName)
                    .font(.subheadline)
                    .bold()
                    .foregroundColor(.primary)
                
                Text("\(ticketDetail.no) ticket\(ticketDetail.no > 1 ? "s" : "")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text("$\(String(format: "%.2f", ticketDetail.amount))")
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(.green)
        }
        .padding(.vertical, 4)
    }
}

struct ParticipantRow: View {
    let participant: ParticipantDetail
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.fill")
                .font(.subheadline)
                .foregroundColor(.orange)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(participant.name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                if let age = participant.age {
                    Text("Age: \(age)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

struct DividerLine: View {
    var body: some View {
        Rectangle()
            .fill(Color(.systemGray5))
            .frame(height: 1)
            .padding(.horizontal, 20)
    }
}

struct DownloadButton: View {
    let pdfUrl: String
    
    var body: some View {
        Button(action: {
            if let url = URL(string: pdfUrl) {
                UIApplication.shared.open(url)
            }
        }) {
            HStack(spacing: 12) {
                Image(systemName: "doc.fill")
                    .font(.headline)
                
                Text("Download Ticket PDF")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Image(systemName: "arrow.down.circle.fill")
                    .font(.title3)
            }
            .foregroundColor(.white)
            .padding(16)
            .background(
                LinearGradient(
                    colors: [Color.orange, Color.orange.opacity(0.8)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .cornerRadius(16)
            .shadow(color: .orange.opacity(0.3), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct LoadingCard: View {
    let message: String
    
    var body: some View {
        ModernCard {
            HStack(spacing: 12) {
                ProgressView()
                    .scaleEffect(0.8)
                
                Text(message)
                    .foregroundColor(.secondary)
                    .font(.subheadline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        }
    }
}

struct LoadingStateView: View {
    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Loading details...")
                .foregroundColor(.secondary)
                .font(.subheadline)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

struct ErrorStateView: View {
    let message: String
    let retryAction: () -> Void
    
    var body: some View {
        ModernCard {
            VStack(spacing: 20) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.orange)
                
                VStack(spacing: 8) {
                    Text("Error Loading Details")
                        .font(.title3)
                        .fontWeight(.semibold)
                    
                    Text(message)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                }
                
                Button("Try Again", action: retryAction)
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.orange)
                    .cornerRadius(12)
            }
            .padding(.vertical, 20)
        }
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
        subtitle: nil,
        displayAmount: "$50.00",
        status: "Paid",
        detailId: 123
    )
    
    NavigationView {
        PurchaseDetailView(record: sampleRecord)
    }
}
// MARK: - Helper to check membership quickly (cached via AccountView)
struct AccountViewHelper {
    static func isActiveMember() -> Bool {
        if let expiryRaw = UserDefaults.standard.string(forKey: "membershipExpiryDate") {
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.dateFormat = "yyyy-MM-dd"
            if let exp = df.date(from: expiryRaw) {
                let today = Calendar.current.startOfDay(for: Date())
                return exp >= today
            }
        }
        return false
    }
}
