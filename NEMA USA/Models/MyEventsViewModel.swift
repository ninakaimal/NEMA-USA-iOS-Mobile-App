//
//  MyEventsViewModel.swift
//  NEMA USA
//
//  Created by Sajith on 6/18/25.
//

import Foundation

@MainActor
class MyEventsViewModel: ObservableObject {
    @Published var upcomingEvents: [PurchaseRecord] = []
    @Published var pastEvents: [PurchaseRecord] = []
    
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let repository = MyEventsRepository()
    
    init() {
        partitionEvents(from: repository.getLocalRecords())
    }
    
    func loadMyEvents() async {
        isLoading = true
        errorMessage = nil
        
        do {
            try await repository.syncRecords()
            partitionEvents(from: repository.getLocalRecords())
        } catch {
            errorMessage = "Failed to sync your events. Please check your connection."
            print(error.localizedDescription)
        }
        
        isLoading = false
    }
    
    private func partitionEvents(from records: [PurchaseRecord]) {
        let now = Date()
        let calendar = Calendar.current
        
        var upcoming: [PurchaseRecord] = []
        var past: [PurchaseRecord] = []
        
        for event in records {
            // If eventDate is nil (TBA), it ALWAYS goes into upcoming.
            guard let eventDate = event.eventDate else {
                upcoming.append(event)
                continue
            }
            
            // If the date is today or in the future, it's upcoming.
            if calendar.startOfDay(for: eventDate) >= calendar.startOfDay(for: now) {
                upcoming.append(event)
            } else {
                past.append(event)
            }
        }
        
        self.upcomingEvents = upcoming
        self.pastEvents = past
    }
}
