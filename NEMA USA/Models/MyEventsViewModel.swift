//
//  MyEventsViewModel.swift
//  NEMA USA
//
//  Created by Sajith on 6/18/25.
//

import Foundation
import CoreData

@MainActor
class MyEventsViewModel: ObservableObject {
    @Published var purchaseRecords: [PurchaseRecord] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var shouldShowLogin: Bool = false
    
    private let networkManager = NetworkManager.shared
    private let viewContext: NSManagedObjectContext
    private var loadTask: Task<Void, Never>? // Track the current load task
    
    private var isAuthenticated: Bool {
        return DatabaseManager.shared.jwtApiToken != nil
    }
    
    init(context: NSManagedObjectContext = PersistenceController.shared.container.viewContext) {
        self.viewContext = context
    }
    
    func loadMyEvents() async {
        // Cancel any existing load task to prevent conflicts
        loadTask?.cancel()
        
        loadTask = Task { @MainActor in
            guard isAuthenticated else {
                self.shouldShowLogin = true
                return
            }
            
            // Don't start a new load if one is already in progress
            guard !isLoading else {
                print("[MyEventsViewModel] Load already in progress, skipping")
                return
            }
            
            isLoading = true
            errorMessage = nil
            
            // CLEAR CODE CACHE - FORCE REFRESH if structure changed - REMOVE with FUTURE VERSION 
            print("[MyEventsViewModel] Clearing old Core Data cache due to structure changes")
            let deleteRequest: NSFetchRequest<NSFetchRequestResult> = CDPurchaseRecord.fetchRequest()
            let deleteResult = NSBatchDeleteRequest(fetchRequest: deleteRequest)
            
            do {
                try viewContext.execute(deleteResult)
                try viewContext.save()
                print("[MyEventsViewModel] Successfully cleared old Core Data cache")
            } catch {
                print("[MyEventsViewModel] Failed to clear cache: \(error)")
            }
            
            // First load from Core Data
            await loadRecordsFromCoreData()
            
            // Only sync from network if we have existing data or if this is the first load
            if !Task.isCancelled {
                await syncFromNetwork()
            }
            
            isLoading = false
        }
        
        await loadTask?.value
    }
    
    func refreshMyEvents() async {
        guard isAuthenticated else {
            self.shouldShowLogin = true
            return
        }
        
        // Cancel any existing task
        loadTask?.cancel()
        
        // For refresh, always sync from network without showing loading state
        await syncFromNetwork()
    }
    
    private func syncFromNetwork() async {
        // Double-check authentication and cancellation
        guard isAuthenticated && !Task.isCancelled else {
            if !isAuthenticated {
                self.shouldShowLogin = true
            }
            return
        }
        
        do {
            print("[MyEventsViewModel] Syncing purchase records from network...")
            let fetchedRecords = try await networkManager.fetchPurchaseRecords()
            
            // Check if task was cancelled during the network request
            guard !Task.isCancelled else {
                print("[MyEventsViewModel] Task was cancelled during network request")
                return
            }
            
            print("[MyEventsViewModel] Fetched \(fetchedRecords.count) records from API")
            
            // Update Core Data with new records
            await saveToCoreData(fetchedRecords)
            
            // Update UI with latest data (only if not cancelled)
            if !Task.isCancelled {
                self.purchaseRecords = fetchedRecords.sorted { record1, record2 in
                    // Sort by event date (most recent first), then by purchase date
                    if let date1 = record1.eventDate, let date2 = record2.eventDate {
                        return date1 > date2
                    } else if record1.eventDate != nil {
                        return true
                    } else if record2.eventDate != nil {
                        return false
                    } else {
                        return record1.purchaseDate > record2.purchaseDate
                    }
                }
                
                // Clear any previous error on successful load
                self.errorMessage = nil
                
                // Notify EventStatusService about the update
                NotificationCenter.default.post(name: NSNotification.Name("PurchaseRecordsUpdated"), object: nil)
            }
            
        } catch let networkError as NetworkError {
            // Only show error if task wasn't cancelled
            guard !Task.isCancelled else {
                print("[MyEventsViewModel] Network request was cancelled, not showing error")
                return
            }
            
            print("[MyEventsViewModel] Network error: \(networkError)")
            switch networkError {
            case .serverError(let message):
                if message.contains("401") || message.contains("authenticate") || message.contains("cancelled") {
                    // Don't show error for cancelled requests
                    if message.contains("cancelled") {
                        print("[MyEventsViewModel] Request was cancelled, using cached data")
                        return
                    }
                    
                    errorMessage = "Please log in again to view your events."
                    // Trigger logout flow
                    NotificationCenter.default.post(name: .didSessionExpire, object: nil)
                } else {
                    errorMessage = "Could not load your events. Please try again."
                }
            default:
                errorMessage = "Could not load your events. Please try again."
            }
        } catch {
            guard !Task.isCancelled else { return }
            
            print("[MyEventsViewModel] Unexpected error: \(error)")
            // Check if it's a cancellation error
            if (error as NSError).code == -999 {
                print("[MyEventsViewModel] Request was cancelled, using cached data")
                return
            }
            errorMessage = "Could not load your events. Please try again."
        }
    }
    
    private func loadRecordsFromCoreData() async {
        let request: NSFetchRequest<CDPurchaseRecord> = CDPurchaseRecord.fetchRequest()
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \CDPurchaseRecord.eventDate, ascending: false),
            NSSortDescriptor(keyPath: \CDPurchaseRecord.purchaseDate, ascending: false)
        ]
        
        do {
            let cdRecords = try viewContext.fetch(request)
            self.purchaseRecords = cdRecords.map { cdRecord in
                PurchaseRecord(
                    recordId: cdRecord.recordId ?? "",
                    type: cdRecord.type ?? "",
                    purchaseDate: cdRecord.purchaseDate ?? Date(),
                    eventDate: cdRecord.eventDate,
                    eventName: cdRecord.eventName ?? "",
                    title: cdRecord.title ?? "",
                    subtitle: cdRecord.subtitle,
                    displayAmount: cdRecord.displayAmount,
                    status: cdRecord.status ?? "",
                    detailId: Int(cdRecord.detailId)
                )
            }
            print("[MyEventsViewModel] Loaded \(cdRecords.count) records from Core Data")
        } catch {
            print("[MyEventsViewModel] Failed to load from Core Data: \(error)")
        }
    }
    
    private func saveToCoreData(_ records: [PurchaseRecord]) async {
        // Check cancellation before saving
        guard !Task.isCancelled else { return }
        
        // Clear existing records to avoid duplicates
        let deleteRequest: NSFetchRequest<NSFetchRequestResult> = CDPurchaseRecord.fetchRequest()
        let deleteRequestResult = NSBatchDeleteRequest(fetchRequest: deleteRequest)
        
        do {
            try viewContext.execute(deleteRequestResult)
            
            // Save new records
            for record in records {
                let cdRecord = CDPurchaseRecord(context: viewContext)
                cdRecord.recordId = record.recordId
                cdRecord.type = record.type
                cdRecord.purchaseDate = record.purchaseDate
                cdRecord.eventDate = record.eventDate
                cdRecord.eventName = record.eventName
                cdRecord.title = record.title
                cdRecord.subtitle = record.subtitle
                cdRecord.displayAmount = record.displayAmount
                cdRecord.status = record.status
                cdRecord.detailId = Int64(record.detailId)
                cdRecord.eventId = record.eventId
            }
            
            if viewContext.hasChanges {
                try viewContext.save()
                print("[MyEventsViewModel] Saved \(records.count) records to Core Data")
            }
        } catch {
            print("[MyEventsViewModel] Failed to save to Core Data: \(error)")
        }
    }
    
    func clearError() {
        errorMessage = nil
    }
    func clearData() {
        purchaseRecords = []
        errorMessage = nil
        isLoading = false
    }
    
    // Clean up when the view model is deinitialized
    deinit {
        loadTask?.cancel()
    }
}
