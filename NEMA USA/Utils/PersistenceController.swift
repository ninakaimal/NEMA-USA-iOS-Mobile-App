//  Persistence.swift (or PersistenceController.swift)
//  NEMA USA
//
//  Created by Sajith on 5/22/25.
//

import CoreData // Make sure this import is present

struct PersistenceController {
    static let shared = PersistenceController()

    // This 'preview' static property is mainly for SwiftUI Previews.
    // If it causes issues before your NSManagedObject subclasses are fully recognized,
    // you can comment out the lines that create specific entity instances.
    static var preview: PersistenceController = {
        let result = PersistenceController(inMemory: true)
        let viewContext = result.container.viewContext
        
        // --- SAMPLE DATA CREATION (Commented out to avoid "unresolved identifier" errors initially) ---
        /*
        // Example: If you want to add sample data for previews later:
        for i in 0..<5 {
            let newItem = CDEvent(context: viewContext) // This line would need CDEvent to be known
            newItem.id = UUID().uuidString // Or your actual ID format
            newItem.title = "Sample Event \(i)"
            newItem.lastUpdatedAt = Date()
            newItem.isRegON = Bool.random()
            newItem.usesPanthi = Bool.random()
            // ... set all other non-optional attributes ...
        }
        */
        // --- END SAMPLE DATA ---
        
        do {
            // Only save if there were actual changes.
            // If you commented out all sample data creation, this 'save' might not be needed here.
            if viewContext.hasChanges {
                try viewContext.save()
            }
        } catch {
            // Replace this implementation with code to handle the error appropriately.
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }
        return result
    }() // End of 'preview'

    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        // Ensure "NEMAAppDataModel" EXACTLY matches your .xcdatamodeld file name
        container = NSPersistentContainer(name: "NEMAAppDataModel")
        
        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        }
        
        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            if let error = error as NSError? {
                // Replace this implementation with code to handle the error appropriately.
                // fatalError() causes the application to generate a crash log and terminate.
                // You should not use this function in a shipping application, although it may be useful during development.
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        })
        container.viewContext.automaticallyMergesChangesFromParent = true // Good for background context merges
    }
}
