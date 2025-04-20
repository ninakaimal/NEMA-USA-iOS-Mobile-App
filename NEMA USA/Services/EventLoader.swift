//
//  EventLoader.swift
//  NEMA USA
//
//  Created by Nina on 4/15/25.
//
import Foundation

class EventLoader: ObservableObject {
    @Published var events: [Event] = []

    init() {
        loadEvents()
    }

    func loadEvents() {
        guard let url = Bundle.main.url(forResource: "events", withExtension: "json") else {
            print("❌ events.json not found")
            return
        }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            events = try decoder.decode([Event].self, from: data)
        } catch {
            print("❌ Error decoding events: \(error)")
        }
    }
}
