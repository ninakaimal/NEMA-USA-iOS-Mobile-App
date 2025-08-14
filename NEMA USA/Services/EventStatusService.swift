//
//  EventStatusService.swift
//  NEMA USA
//
//  Created by Arjun Kaimal on 7/22/25.
//
import Foundation
import CoreData

@MainActor
class EventStatusService: ObservableObject {
    static let shared = EventStatusService()
    
    @Published private var purchaseRecords: [PurchaseRecord] = []
    
    // PERFORMANCE: Cache status results to avoid repeated calculations
    private var statusCache: [String: EventUserStatuses] = [:]
    private var eventNameCache: [String: String] = [:] // eventId -> normalized name
    
    private let viewContext: NSManagedObjectContext
    private var lastCacheUpdate: Date = Date.distantPast
    private let cacheValidityDuration: TimeInterval = 300 // 5 minutes
    
    // PERFORMANCE: Debounce updates to prevent excessive refreshes
    private var updateTask: Task<Void, Never>?
    
    private init(context: NSManagedObjectContext = PersistenceController.shared.container.viewContext) {
        self.viewContext = context
        loadPurchaseRecordsFromCoreData()
        buildCaches()
        
        // Listen for updates from MyEventsViewModel
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(debouncedRefresh),
            name: NSNotification.Name("PurchaseRecordsUpdated"),
            object: nil
        )
        
        // REMOVED: Automatic event updates listener to prevent cascading updates
        // Only manual refresh when really needed
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        updateTask?.cancel()
    }
    
    @objc private func debouncedRefresh() {
        // Cancel previous update task
        updateTask?.cancel()
        
        // Debounce updates - only refresh after 1 second of no new requests
        updateTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            
            if !Task.isCancelled {
                self.refreshCaches()
            }
        }
    }
    
    private func loadPurchaseRecordsFromCoreData() {
        let request: NSFetchRequest<CDPurchaseRecord> = CDPurchaseRecord.fetchRequest()
        
        do {
            let cdRecords = try viewContext.fetch(request)
            self.purchaseRecords = cdRecords.compactMap { cdRecord in
                // PERFORMANCE: Only include valid records upfront
                guard let recordId = cdRecord.recordId, !recordId.isEmpty,
                      let type = cdRecord.type, !type.isEmpty,
                      let eventName = cdRecord.eventName, !eventName.isEmpty else {
                    return nil
                }
                
                return PurchaseRecord(
                    recordId: recordId,
                    type: type,
                    purchaseDate: cdRecord.purchaseDate ?? Date(),
                    eventDate: cdRecord.eventDate,
                    eventName: eventName,
                    title: cdRecord.title ?? "",
                    subtitle: cdRecord.subtitle,
                    displayAmount: cdRecord.displayAmount,
                    status: cdRecord.status ?? "",
                    detailId: Int(cdRecord.detailId),
                    eventId: cdRecord.eventId
                )
            }
            print("[EventStatusService] Loaded \(self.purchaseRecords.count) valid purchase records from Core Data")
        } catch {
            print("[EventStatusService] Failed to load from Core Data: \(error)")
        }
    }
    
    private func refreshCaches() {
        statusCache.removeAll()
        buildCaches()
        lastCacheUpdate = Date()
        print("[EventStatusService] Refreshed caches with \(purchaseRecords.count) records")
    }
    
    private func buildCaches() {
        // PERFORMANCE: Pre-build normalized event names for faster lookups
        let eventRepository = EventRepository()
        
        Task {
            await eventRepository.loadEventsFromCoreData()
            
            // Build event name cache
            for event in eventRepository.events {
                eventNameCache[event.id] = normalizeEventName(event.title)
            }
        }
    }
    
    // MARK: - Optimized Status Checking
    
    func getUserStatuses(for event: Event) -> EventUserStatuses {
        // PERFORMANCE: Check cache first
        if let cached = statusCache[event.id] {
            return cached
        }
        
        // PERFORMANCE: Use simple, fast matching only
        let result = getStatusesForEvent(event)
        
        // Cache the result
        statusCache[event.id] = result
        
        return result
    }
    
    private func getStatusesForEvent(_ event: Event) -> EventUserStatuses {
        // FIRST: Try to match by eventId if available
        let matchingRecords = purchaseRecords.filter { record in
            // If both have eventId, use exact match
            if let recordEventId = record.eventId, !recordEventId.isEmpty {
                return recordEventId == event.id
            }
            
            // FALLBACK: For old records without eventId, use name matching
            let normalizedEventName = eventNameCache[event.id] ?? normalizeEventName(event.title)
            let normalizedRecordName = normalizeEventName(record.eventName)
            return normalizedRecordName == normalizedEventName
        }
        
        // DEBUG: Add this to see what's matching
        if event.title.contains("Onam 2025") && !matchingRecords.isEmpty {
            print("🔍 [EventStatusService] Event '\(event.title)' (ID: \(event.id)) matched \(matchingRecords.count) records:")
            for record in matchingRecords {
                print("  - Type: \(record.type), Status: \(record.status), EventID: \(record.eventId ?? "nil"), EventName: \(record.eventName)")
            }
        }
        
        let hasPurchasedTickets = matchingRecords.contains { record in
            record.type.lowercased().contains("ticket") && isRecordValid(record)
        }
        
        // Separate regular registrations from waitlist
        let hasRegisteredPrograms = matchingRecords.contains { record in
            record.type.lowercased().contains("program") &&
            !isWaitlistStatus(record.status) &&
            isRecordValid(record)
        }
        
        let hasWaitlistPrograms = matchingRecords.contains { record in
            (record.type.lowercased().contains("program") && isWaitlistStatus(record.status)) ||
            (record.type.lowercased().contains("ticket") && isWaitlistStatus(record.status))
        }
        
        return EventUserStatuses(
            hasPurchasedTickets: hasPurchasedTickets,
            hasRegisteredPrograms: hasRegisteredPrograms,
            hasWaitlistPrograms: hasWaitlistPrograms
        )
    }

    private func isWaitlistStatus(_ status: String) -> Bool {
        let waitlistStatuses = ["wait_list", "wait list", "waitlist", "waiting_list"]
        return waitlistStatuses.contains(status.lowercased())
    }
    
    // MARK: - Simplified Helper Functions
    
    private func normalizeEventName(_ name: String) -> String {
        // PERFORMANCE: Simplified normalization - just lowercase and trim
        return name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func isRecordValid(_ record: PurchaseRecord) -> Bool {
        let validStatuses = ["paid", "success", "confirmed", "wait_list", "wait list"]
        return validStatuses.contains(record.status.lowercased())
    }
    
    // MARK: - Batch Operations (Optimized)
    
    func getUserStatuses(for events: [Event]) -> [String: EventUserStatuses] {
        // PERFORMANCE: Check if cache needs refresh (only every 5 minutes)
        let now = Date()
        if now.timeIntervalSince(lastCacheUpdate) > cacheValidityDuration {
            refreshCaches()
        }
        
        var statusMap: [String: EventUserStatuses] = [:]
        
        // PERFORMANCE: Process in batches to avoid blocking UI
        let batchSize = 20
        for i in stride(from: 0, to: events.count, by: batchSize) {
            let endIndex = min(i + batchSize, events.count)
            let batch = Array(events[i..<endIndex])
            
            for event in batch {
                statusMap[event.id] = getUserStatuses(for: event)
            }
        }
        
        return statusMap
    }
    
    // MARK: - Manual Refresh Only
    
    func forceRefresh() async {
        await Task { @MainActor in
            loadPurchaseRecordsFromCoreData()
            refreshCaches()
        }.value
    }
    
    // MARK: - Simplified Debug
    
    func debugInfo() -> String {
        return """
        EventStatusService Debug Info:
        - Purchase Records: \(purchaseRecords.count)
        - Cached Statuses: \(statusCache.count)
        - Last Cache Update: \(lastCacheUpdate.formatted())
        """
    }
}
