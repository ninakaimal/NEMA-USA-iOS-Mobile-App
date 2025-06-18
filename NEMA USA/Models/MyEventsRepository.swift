//
//  MyEventsRepository.swift
//  NEMA USA
//
//  Created by Sajith on 6/18/25.
//
import Foundation
import CoreData

@MainActor
class MyEventsRepository: ObservableObject {
    private let networkManager = NetworkManager.shared
    private let viewContext: NSManagedObjectContext

    init(context: NSManagedObjectContext = PersistenceController.shared.container.viewContext) {
        self.viewContext = context
    }

    /// Fetches records from the local Core Data database.
    func getLocalRecords() -> [PurchaseRecord] {
        let request: NSFetchRequest<CDPurchaseRecord> = CDPurchaseRecord.fetchRequest()
        // Sort by event date to maintain chronological order
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CDPurchaseRecord.eventDate, ascending: false)]
        
        do {
            let cdRecords = try viewContext.fetch(request)
            return cdRecords.map { self.mapToPurchaseRecord(cdRecord: $0) }
        } catch {
            print("❌ Failed to fetch records from Core Data: \(error)")
            return []
        }
    }

    /// Fetches the latest records from the network and updates the local database.
    func syncRecords() async throws {
        let lastSyncTimestamp = UserDefaults.standard.object(forKey: "lastSyncMyEvents") as? Date
        
        // Pass the last sync date to the network manager
        let fetchedRecords = try await networkManager.fetchPurchaseRecords(since: lastSyncTimestamp)

        if fetchedRecords.isEmpty {
            print("ℹ️ No new event records to sync.")
            return
        }

        // Use the recordId as a unique identifier for finding existing records
        let existingRecordIDs = Set(fetchedRecords.map { $0.recordId })
        let fetchRequest: NSFetchRequest<CDPurchaseRecord> = CDPurchaseRecord.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "recordId IN %@", existingRecordIDs)
        let existingCDRecords = try viewContext.fetch(fetchRequest)
        let existingCDRecordsDict = Dictionary(uniqueKeysWithValues: existingCDRecords.map { ($0.recordId!, $0) })
        
        // Update existing records or create new ones
        for recordData in fetchedRecords {
            let cdRecord = existingCDRecordsDict[recordData.recordId] ?? CDPurchaseRecord(context: viewContext)
            self.update(cdRecord: cdRecord, with: recordData)
        }
        
        if viewContext.hasChanges {
            try viewContext.save()
            UserDefaults.standard.set(Date(), forKey: "lastSyncMyEvents")
            print("✅ Successfully synced \(fetchedRecords.count) event records to Core Data.")
        }
    }
    
    // MARK: - Mappers
    
    private func update(cdRecord: CDPurchaseRecord, with record: PurchaseRecord) {
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
    
    private func mapToPurchaseRecord(cdRecord: CDPurchaseRecord) -> PurchaseRecord {
        return PurchaseRecord(
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
}
