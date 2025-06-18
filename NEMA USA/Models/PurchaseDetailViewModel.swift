//
//  PurchaseDetailViewModel.swift
//  NEMA USA
//
//  Created by Sajith on 6/18/25.
//
import Foundation

@MainActor
class PurchaseDetailViewModel: ObservableObject {
    @Published var ticketDetail: TicketPurchaseDetailResponse?
    @Published var programDetail: Participant?
    
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let networkManager = NetworkManager.shared
    
    func loadDetails(for record: PurchaseRecord) async {
        guard !isLoading else { return }
        
        isLoading = true
        errorMessage = nil
        
        do {
            if record.type == "Ticket Purchase" {
                ticketDetail = try await networkManager.fetchTicketRecordDetail(id: record.detailId)
            } else {
                programDetail = try await networkManager.fetchProgramRecordDetail(id: record.detailId)
            }
        } catch {
            errorMessage = "Could not load details for this record. Please try again."
            print(error.localizedDescription)
        }
        
        isLoading = false
    }
}
