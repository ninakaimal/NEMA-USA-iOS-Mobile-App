//
//  EventRegistrationViewModel.swift
//  NEMA USA
//
//  Created by Sajith on 5/22/25.

import Foundation
import Combine // Optional, if you later want to use Combine publishers more extensively

@MainActor // Ensures changes to @Published properties happen on the main thread
class EventRegistrationViewModel: ObservableObject {

    // MARK: - Published Properties for UI
    @Published var availableTicketTypes: [EventTicketType] = []
    @Published var availablePanthis: [Panthi] = []
    
    @Published var selectedPanthiId: Int? = nil // Use Int? to allow for no selection initially
    @Published var ticketQuantities: [Int: Int] = [:] // Key: EventTicketType.id, Value: quantity

    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    // MARK: - Dependencies
    private let networkManager = NetworkManager.shared // Uses your existing shared instance
    private let eventRepository: EventRepository // To interact with Core Data sync logic

    // Access current user profile to check membership status
    private var currentUser: UserProfile? {
        return DatabaseManager.shared.currentUser
    }

    // MARK: - Initialization
    init(eventRepository: EventRepository = EventRepository()) { // Allows injecting for testing
        self.eventRepository = eventRepository
    }

    // MARK: - Data Loading
    func loadPrerequisites(for event: Event) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        
        // Clear previous data
        self.availableTicketTypes = []
        self.availablePanthis = []
        self.ticketQuantities = [:]
        self.selectedPanthiId = nil

//        print("🚀 [EventRegVM] Loading prerequisites for event: \(event.title) (ID: \(event.id))")

        do {
            // --- Sync and Fetch Ticket Types ---
            // Ask repository to sync (fetches from network, saves to Core Data)
            // The repository's syncTicketTypes method itself will fetch from network and save to CD.
            // For the UI to get the data immediately after sync for *this specific view*,
            // we might fetch directly from NetworkManager here OR enhance EventRepository
            // to return the fetched items from its sync methods.
            // For today's sprint, direct fetch after sync is simpler.

            await eventRepository.syncTicketTypes(forEventID: event.id)
            // Then, fetch the (potentially updated) data. Ideally, this comes from a Core Data fetch.
            // For now, let's re-fetch via NetworkManager to ensure we have the latest for this screen.
            let fetchedTicketTypes = try await networkManager.fetchTicketTypes(forEventId: event.id)
            self.availableTicketTypes = fetchedTicketTypes
            self.ticketQuantities = Dictionary(uniqueKeysWithValues: fetchedTicketTypes.map { ($0.id, 0) })
            print("✅ [EventRegVM] Loaded \(fetchedTicketTypes.count) ticket types.")

            // --- Sync and Fetch Panthis (if applicable) ---
            if event.usesPanthi ?? false {
                await eventRepository.syncPanthis(forEventID: event.id)
                let fetchedPanthis = try await networkManager.fetchPanthis(forEventId: event.id)
                self.availablePanthis = fetchedPanthis
                print("✅ [EventRegVM] Loaded \(fetchedPanthis.count) panthis.")
            } else {
                print("ℹ️ [EventRegVM] Event does not use panthis.")
            }
            
        } catch let networkError as NetworkError {
            self.errorMessage = "Failed to load event options: \(networkError)" // More user-friendly message later
            print("❌ [EventRegVM] NetworkError loading prerequisites: \(networkError)")
        } catch {
            self.errorMessage = "An unexpected error occurred while loading event options."
            print("❌ [EventRegVM] Error loading prerequisites: \(error.localizedDescription)")
        }
        isLoading = false
    }

    // MARK: - Price Calculation Logic
    func price(for ticketType: EventTicketType) -> Double {
        // Determine if the current user is a member
        let isUserMember = currentUser?.isMember ?? false
        let today = Date()

        // 1. Check for active Early Bird prices
        if let earlyBirdEndDate = ticketType.earlyBirdEndDate,
           Calendar.current.startOfDay(for: today) <= Calendar.current.startOfDay(for: earlyBirdEndDate) { // Inclusive of end date
            if isUserMember, let earlyMemberPrice = ticketType.earlyBirdMemberPrice, earlyMemberPrice > 0 {
                return earlyMemberPrice
            } else if let earlyPublicPrice = ticketType.earlyBirdPublicPrice, earlyPublicPrice > 0 {
                return earlyPublicPrice
            }
            // If specific early bird prices are 0 or nil, fall through to regular pricing
        }

        // 2. Regular pricing
        if isUserMember, let memberPrice = ticketType.memberPrice, memberPrice > 0 {
            return memberPrice
        }
        
        // 3. Default to public price
        return ticketType.publicPrice
    }

    // MARK: - Computed Properties for UI
    var totalAmount: Double {
        availableTicketTypes.reduce(0.0) { currentTotal, ticketType in
            let quantity = ticketQuantities[ticketType.id] ?? 0
            let unitPrice = price(for: ticketType)
            return currentTotal + (Double(quantity) * unitPrice)
        }
    }

    var purchaseSummary: String {
        var summaryLines: [String] = []
        if let panthiId = selectedPanthiId, let panthi = availablePanthis.first(where: { $0.id == panthiId }) {
            summaryLines.append("Slot: \(panthi.name)")
        }
        for ticketType in availableTicketTypes {
            if let quantity = ticketQuantities[ticketType.id], quantity > 0 {
                summaryLines.append("\(ticketType.typeName): \(quantity) @ $\(String(format: "%.2f", price(for: ticketType)))")
            }
        }
        summaryLines.append("Total: $\(String(format: "%.2f", totalAmount))")
        return summaryLines.joined(separator: "\n")
    }
    
    func canProceedToPurchase(acceptedTerms: Bool, eventUsesPanthi: Bool, availablePanthisNonEmpty: Bool) -> Bool {
        guard acceptedTerms else { return false }
        guard totalAmount > 0 else { return false } // Must select at least one ticket

        if eventUsesPanthi && availablePanthisNonEmpty { // If panthis are used and available
            guard selectedPanthiId != nil else { return false } // Must select a panthi
        }
        return true
    }
}
