//
//  EventRepository.swift
//  NEMA USA
//  Created by Nina on 4/15/25.
// Updated by Sajith on 5/22/2025
//
import Foundation

import Foundation
import CoreData // Import CoreData

class EventRepository: ObservableObject {
    // This will now be populated from Core Data, which is synced from the network
    @Published var events: [Event] = []
    @Published var isLoading: Bool = false
    @Published var lastSyncErrorMessage: String?
    
    private let networkManager = NetworkManager.shared
    private let viewContext: NSManagedObjectContext
    
    init(context: NSManagedObjectContext = PersistenceController.shared.container.viewContext) {
        self.viewContext = context
    }
    
    // --- NEW SYNC METHODS ---
    
    @MainActor // Ensure Core Data operations and @Published updates are on the main thread
    func syncAllEvents(forceFullSync: Bool = false) async {
        guard !isLoading else {
            print("[EventRepository] Sync already in progress.")
            return
        }
        isLoading = true
        lastSyncErrorMessage = nil
        
        let lastSyncTimestamp = forceFullSync ? nil : UserDefaults.standard.object(forKey: "lastSyncEvents") as? Date
        print("[EventRepository] Syncing all events. Last sync: \(lastSyncTimestamp?.description ?? "Never (forcing full sync: \(forceFullSync))")")
        
        do {
            let (fetchedEventsData, deletedEventIds) = try await networkManager.fetchEvents(since: lastSyncTimestamp)
            print("[EventRepository] Fetched \(fetchedEventsData.count) events from API, \(deletedEventIds.count) to be processed as deleted.")
            
            if !fetchedEventsData.isEmpty {
                let existingEventIDs = Set(fetchedEventsData.map { $0.id })
                let fetchRequest: NSFetchRequest<CDEvent> = CDEvent.fetchRequest()
                fetchRequest.predicate = NSPredicate(format: "id IN %@", existingEventIDs)
                let existingCDEventsArray = try viewContext.fetch(fetchRequest)
                let validCDEvents = existingCDEventsArray.filter { $0.id != nil && !$0.id!.isEmpty }
                let existingCDEventsDict = Dictionary(uniqueKeysWithValues: validCDEvents.map { ($0.id!, $0) })

                for eventData in fetchedEventsData { // <<<<<<<< CORRECTLY USES fetchedEventsData
                    let cdEvent = existingCDEventsDict[eventData.id] ?? CDEvent(context: viewContext)
                    // ... (mapping properties) ...
                    cdEvent.id = eventData.id // Ensure id is set for new objects too
                    cdEvent.title = eventData.title
                    cdEvent.plainDescription = eventData.plainDescription
                    cdEvent.htmlDescription = eventData.htmlDescription
                    cdEvent.location = eventData.location
                    cdEvent.categoryName = eventData.categoryName
                    cdEvent.eventCatId = eventData.eventCatId.map { Int32($0) } ?? 0
                    cdEvent.imageUrl = eventData.imageUrl
                    // cdEvent.isTBD removed
                    cdEvent.isRegON = eventData.isRegON ?? false
                    cdEvent.isTktON = eventData.isTktON ?? false
                    cdEvent.showBuyTickets = eventData.showBuyTickets ?? false
                    cdEvent.date = eventData.date
                    cdEvent.timeString = eventData.timeString
                    cdEvent.eventLink = eventData.eventLink
                    cdEvent.usesPanthi = eventData.usesPanthi ?? false
                    cdEvent.showBuyTickets = eventData.showBuyTickets ?? false
                    cdEvent.lastUpdatedAt = eventData.lastUpdatedAt ?? Date()
                }
            }
            
            // Handle Deletions (simplified for now if deletedEventIds isn't fully supported by API yet)
            if !deletedEventIds.isEmpty {
                let deleteFetchRequest: NSFetchRequest<CDEvent> = CDEvent.fetchRequest()
                deleteFetchRequest.predicate = NSPredicate(format: "id IN %@", deletedEventIds)
                do {
                    let eventsToDelete = try viewContext.fetch(deleteFetchRequest)
                    if !eventsToDelete.isEmpty {
                        print("[EventRepository] Deleting \(eventsToDelete.count) events from Core Data...")
                        for eventObject in eventsToDelete {
                            viewContext.delete(eventObject)
                        }
                    }
                } catch {
                    print("⚠️ [EventRepository] Error fetching events to delete: \(error)")
                }
            }
            
            if viewContext.hasChanges {
                try viewContext.save()
                UserDefaults.standard.set(Date(), forKey: "lastSyncEvents")
                print("✅ [EventRepository] Successfully synced and saved events to Core Data.")
            } else {
                print("ℹ️ [EventRepository] No event changes to save after sync.")
            }
            await loadEventsFromCoreData() // fetchLimit: 10) // Keep this limit if needed to update the UI with a limited set
            
        } catch let networkError as NetworkError { // Catch specific NetworkError
            lastSyncErrorMessage = "Network Error during event sync: \(networkError)"
            print("❌ [EventRepository] Network error syncing events: \(networkError)")
        } catch { // Catch any other errors
            lastSyncErrorMessage = "General error during event sync: \(error.localizedDescription)"
            print("❌ [EventRepository] Error syncing events: \(error.localizedDescription)")
        }
        isLoading = false
    }
    
    // Method to sync ticket types for a specific event
    @MainActor
    func syncTicketTypes(forEventID eventID: String, eventCDObject: CDEvent? = nil) async {
        // ... (Implementation as provided in previous step for EventRepository, using networkManager) ...
        // ... (Ensure to call loadEventsFromCoreData() or a more targeted update if needed) ...
        guard !isLoading else { return }
        isLoading = true
        print("[EventRepository] Syncing ticket types for event ID: \(eventID)")
        do {
            let fetchedTicketTypes = try await networkManager.fetchTicketTypes(forEventId: eventID)
            print("[EventRepository] Fetched \(fetchedTicketTypes.count) ticket types for event \(eventID).")
            
            let parentEvent: CDEvent
            if let providedEventObject = eventCDObject {
                parentEvent = providedEventObject
            } else {
                let eventFetchRequest: NSFetchRequest<CDEvent> = CDEvent.fetchRequest()
                eventFetchRequest.predicate = NSPredicate(format: "id == %@", eventID as NSString)
                guard let fetchedParentEvent = try viewContext.fetch(eventFetchRequest).first else {
                    print("⚠️ [EventRepository] Event with ID \(eventID) not found in Core Data. Cannot sync ticket types.")
                    isLoading = false
                    return
                }
                parentEvent = fetchedParentEvent
            }
            
            // Simple Upsert Logic for TicketTypes
            for ttData in fetchedTicketTypes {
                let ttFetchRequest: NSFetchRequest<CDEventTicketType> = CDEventTicketType.fetchRequest()
                ttFetchRequest.predicate = NSPredicate(format: "id == %lld AND event == %@", Int64(ttData.id), parentEvent)
                
                var cdTicketType: CDEventTicketType
                if let existingTT = try viewContext.fetch(ttFetchRequest).first {
                    cdTicketType = existingTT
                } else {
                    cdTicketType = CDEventTicketType(context: viewContext)
                    cdTicketType.id = Int64(ttData.id)
                }
                
                cdTicketType.typeName = ttData.typeName
                cdTicketType.publicPrice = ttData.publicPrice
                cdTicketType.memberPrice = ttData.memberPrice ?? 0
                cdTicketType.earlyBirdPublicPrice = ttData.earlyBirdPublicPrice ?? 0
                cdTicketType.earlyBirdMemberPrice = ttData.earlyBirdMemberPrice ?? 0
                cdTicketType.earlyBirdEndDate = ttData.earlyBirdEndDate
                cdTicketType.currencyCode = ttData.currencyCode
                cdTicketType.isTicketTypeMemberExclusive = ttData.isTicketTypeMemberExclusive ?? false
                cdTicketType.lastUpdatedAt = ttData.lastUpdatedAt
                cdTicketType.event = parentEvent
            }
            
            if viewContext.hasChanges {
                try viewContext.save()
                print("✅ [EventRepository] Successfully synced ticket types for event ID: \(eventID)")
            } else {
                print("ℹ️ [EventRepository] No ticket type changes for event ID: \(eventID)")
            }
        } catch {
            print("❌ [EventRepository] Error syncing ticket types for event \(eventID): \(error.localizedDescription)")
        }
        isLoading = false
    }
    
    // Method to sync panthis for a specific event
    @MainActor
    func syncPanthis(forEventID eventID: String, eventCDObject: CDEvent? = nil) async {
        // ... (Implementation as provided in previous step for EventRepository, using networkManager) ...
        // ... (Ensure to call loadEventsFromCoreData() or a more targeted update if needed) ...
        guard !isLoading else { return }
        isLoading = true
        print("[EventRepository] Syncing panthis for event ID: \(eventID)")
        do {
            let fetchedPanthis = try await networkManager.fetchPanthis(forEventId: eventID)
            print("[EventRepository] Fetched \(fetchedPanthis.count) panthis for event \(eventID).")
            
            let parentEvent: CDEvent
            if let providedEventObject = eventCDObject {
                parentEvent = providedEventObject
            } else {
                let eventFetchRequest: NSFetchRequest<CDEvent> = CDEvent.fetchRequest()
                eventFetchRequest.predicate = NSPredicate(format: "id == %@", eventID as NSString)
                guard let fetchedParentEvent = try viewContext.fetch(eventFetchRequest).first else {
                    print("⚠️ [EventRepository] Event with ID \(eventID) not found. Cannot sync panthis.")
                    isLoading = false
                    return
                }
                parentEvent = fetchedParentEvent
            }
            
            if !parentEvent.usesPanthi && fetchedPanthis.isEmpty {
                print("ℹ️ [EventRepository] Event \(eventID) does not use panthis or no panthis fetched, skipping panthi sync.")
                isLoading = false
                return
            }
            
            for panthiData in fetchedPanthis {
                let panthiFetchRequest: NSFetchRequest<CDPanthi> = CDPanthi.fetchRequest()
                panthiFetchRequest.predicate = NSPredicate(format: "id == %lld AND event == %@", Int64(panthiData.id), parentEvent)
                
                var cdPanthi: CDPanthi
                if let existingPanthi = try viewContext.fetch(panthiFetchRequest).first {
                    cdPanthi = existingPanthi
                } else {
                    cdPanthi = CDPanthi(context: viewContext)
                    cdPanthi.id = Int64(panthiData.id)
                }
                
                cdPanthi.name = panthiData.name
                cdPanthi.panthiDescription = panthiData.description
                cdPanthi.availableSlots = Int32(panthiData.availableSlots)
                cdPanthi.totalSlots = panthiData.totalSlots.map { Int32($0) } ?? 0
                cdPanthi.lastUpdatedAt = panthiData.lastUpdatedAt
                cdPanthi.event = parentEvent
            }
            
            if viewContext.hasChanges {
                try viewContext.save()
                print("✅ [EventRepository] Successfully synced panthis for event ID: \(eventID)")
            } else {
                print("ℹ️ [EventRepository] No panthi changes for event ID: \(eventID)")
            }
        } catch {
            print("❌ [EventRepository] Error syncing panthis for event \(eventID): \(error.localizedDescription)")
        }
        isLoading = false
    }
    
    @MainActor
    func syncPrograms(forEventID eventID: String) async -> [EventProgram] {
        print("[EventRepository] Syncing programs for event ID: \(eventID)")
        do {
            let fetchedPrograms = try await networkManager.fetchPrograms(forEventId: eventID)
            print("[EventRepository] Fetched \(fetchedPrograms.count) programs for event \(eventID).")
            
            // Get the parent CDEvent object from Core Data
            let eventFetchRequest: NSFetchRequest<CDEvent> = CDEvent.fetchRequest()
            eventFetchRequest.predicate = NSPredicate(format: "id == %@", eventID as NSString)
            guard let parentEvent = try viewContext.fetch(eventFetchRequest).first else {
                print("⚠️ [EventRepository] Event with ID \(eventID) not found. Cannot sync programs.")
                return []
            }
            
            // Clear old programs to ensure data is fresh
            if let existingPrograms = parentEvent.programs as? Set<CDEventProgram> {
                for program in existingPrograms {
                    viewContext.delete(program)
                }
            }
            
            // Save the new programs and their categories to Core Data
            for programData in fetchedPrograms {
                let cdProgram = CDEventProgram(context: viewContext)
                cdProgram.id = programData.id
                cdProgram.name = programData.name
                cdProgram.time = programData.time
                cdProgram.rulesAndGuidelines = programData.rulesAndGuidelines
                cdProgram.registrationStatus = programData.registrationStatus
                
                var categorySet = Set<CDProgramCategory>()
                for categoryData in programData.categories {
                    let cdCategory = CDProgramCategory(context: viewContext)
                    cdCategory.id = Int64(categoryData.id)
                    cdCategory.name = categoryData.name
                    categorySet.insert(cdCategory)
                }
                cdProgram.categories = categorySet as NSSet
                cdProgram.event = parentEvent
            }
            
            if viewContext.hasChanges {
                try viewContext.save()
                print("✅ [EventRepository] Successfully synced programs for event ID: \(eventID)")
            }
            
            // Return the freshly fetched data for immediate UI use
            return fetchedPrograms
            
        } catch {
            print("❌ [EventRepository] Error syncing programs for event \(eventID): \(error.localizedDescription)")
            return [] // Return an empty array on error
        }
    }
    
    // --- Method to load events from Core Data and publish them ---
    @MainActor
    func loadEventsFromCoreData(fetchLimit: Int = 30) async { // Add a parameter with a default
        let request: NSFetchRequest<CDEvent> = CDEvent.fetchRequest()
        // Sort by date descending to get the latest events
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CDEvent.date, ascending: false)]
        request.fetchLimit = fetchLimit // Apply the limit
        
        do {
            let cdEvents = try viewContext.fetch(request)
            // Map CDEvent objects back to Event structs for the UI
            self.events = cdEvents.map { cdEvent -> Event in
                // Ensure all properties of Event struct are populated from cdEvent.
                return Event(
                    id: cdEvent.id ?? "",
                    title: cdEvent.title ?? "No Title",
                    plainDescription: cdEvent.plainDescription,
                    htmlDescription: cdEvent.htmlDescription,   
                    location: cdEvent.location ?? "To be Announced",
                    categoryName: cdEvent.categoryName,
                    eventCatId: (cdEvent.eventCatId == 0 && cdEvent.categoryName == nil) ? nil : Int(cdEvent.eventCatId), // If 0 and no name implies nil
                    imageUrl: cdEvent.imageUrl,
                    isRegON: cdEvent.isRegON,
                    isTktON: cdEvent.isTktON,
                    showBuyTickets: cdEvent.showBuyTickets,
                    date: cdEvent.date,
                    timeString: cdEvent.timeString,
                    eventLink: cdEvent.eventLink,
                    usesPanthi: cdEvent.usesPanthi,
                    lastUpdatedAt: cdEvent.lastUpdatedAt ?? Date() // Provide a default if lastUpdatedAt is optional in CD (it shouldn't be)
                )
            }
            print("✅ [EventRepository] Loaded a max of \(fetchLimit) events (found \(cdEvents.count)) from Core Data.")
        } catch {
            print("❌ [EventRepository] Failed to fetch events from Core Data: \(error.localizedDescription)")
            lastSyncErrorMessage = "Failed to load local events."
        }
    }
}  // End of File
