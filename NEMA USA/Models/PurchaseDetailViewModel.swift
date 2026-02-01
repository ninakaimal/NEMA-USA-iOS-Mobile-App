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

    @Published var isWithdrawing = false
    @Published var withdrawSuccess = false
    @Published var withdrawErrorMessage: String?
    @Published var withdrawSuccessMessage: String?

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

    func withdrawRegistration(participantId: Int) async {
        guard !isWithdrawing else { return }

        isWithdrawing = true
        withdrawErrorMessage = nil
        withdrawSuccess = false
        withdrawSuccessMessage = nil

        do {
            // Step 1: Initiate withdrawal
            let withdrawResponse = try await networkManager.withdrawProgramRegistration(participantId: participantId)

            // Step 2: Check if refund is required
            if withdrawResponse.refund_required, let refundData = withdrawResponse.refund_data {
                print("🔄 [PurchaseDetailViewModel] Refund required. Processing refund...")

                // Process refund
                let refundResponse = try await networkManager.processRefund(
                    participantId: refundData.participant_id,
                    amount: refundData.amount,
                    saleId: refundData.sale_id
                )

                // Set success message from refund response
                withdrawSuccessMessage = refundResponse.message
                withdrawSuccess = true
                print("✅ [PurchaseDetailViewModel] Refund processed: \(refundResponse.refund_status)")

            } else {
                // No refund needed - simple withdrawal
                withdrawSuccessMessage = withdrawResponse.message
                withdrawSuccess = true
                print("✅ [PurchaseDetailViewModel] Withdrawal completed without refund")
            }

            // Reload details to get updated status
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 second delay before reload
            if let detail = programDetail {
                // Create a mock record to reload with
                let mockRecord = PurchaseRecord(
                    recordId: "program-\(participantId)",
                    type: "Program Registration",
                    purchaseDate: Date(),
                    eventDate: nil,
                    eventName: "",
                    title: "",
                    subtitle: nil,
                    displayAmount: nil,
                    status: "cancelled",
                    detailId: participantId,
                    eventId: nil
                )
                await loadDetails(for: mockRecord)
            }
        } catch let error as NetworkError {
            switch error {
            case .serverError(let message):
                withdrawErrorMessage = message
            case .invalidResponse:
                withdrawErrorMessage = "Invalid response from server. Please try again."
            case .decodingError:
                withdrawErrorMessage = "Failed to process withdrawal. Please try again."
            }
            print("❌ [PurchaseDetailViewModel] Withdrawal error: \(error)")
        } catch {
            withdrawErrorMessage = "Failed to withdraw registration. Please try again."
            print("❌ [PurchaseDetailViewModel] Withdrawal error: \(error.localizedDescription)")
        }

        isWithdrawing = false
    }
}
