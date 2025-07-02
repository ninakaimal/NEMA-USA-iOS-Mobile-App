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
    
    private var isAuthenticated: Bool {
        return DatabaseManager.shared.jwtApiToken != nil
    }
    
    init(context: NSManagedObjectContext = PersistenceController.shared.container.viewContext) {
        self.viewContext = context
    }
    
    func loadMyEvents() async {
        guard isAuthenticated else {
            self.shouldShowLogin = true
            return
        }
        
        guard !isLoading else { return }
        
        isLoading = true
        errorMessage = nil
        
        // First load from Core Data
        await loadRecordsFromCoreData()
        
        // Then sync from network
        await syncFromNetwork()
        
        isLoading = false
    }
    
    func refreshMyEvents() async {
        guard isAuthenticated else {
            self.shouldShowLogin = true
            return
        }
        await syncFromNetwork()
    }
    
    private func syncFromNetwork() async {
        // Double-check authentication
        guard isAuthenticated else {
            self.shouldShowLogin = true
            return
        }
        do {
            print("[MyEventsViewModel] Syncing purchase records from network...")
            let fetchedRecords = try await networkManager.fetchPurchaseRecords()
            print("[MyEventsViewModel] Fetched \(fetchedRecords.count) records from API")
            
            // Update Core Data with new records
            await saveToCoreData(fetchedRecords)
            
            // Update UI with latest data
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
            
        } catch let networkError as NetworkError {
            print("[MyEventsViewModel] Network error: \(networkError)")
            switch networkError {
            case .serverError(let message):
                if message.contains("401") || message.contains("authenticate") {
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
            print("[MyEventsViewModel] Unexpected error: \(error)")
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
                    displayAmount: cdRecord.displayAmount ?? "",
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
                cdRecord.displayAmount = record.displayAmount
                cdRecord.status = record.status
                cdRecord.detailId = Int64(record.detailId)
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
}
