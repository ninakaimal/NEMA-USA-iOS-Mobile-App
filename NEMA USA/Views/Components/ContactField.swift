//
//  ContactField.swift
//  NEMA USA
//
//  Created by Nina on 4/15/25.
//
import SwiftUI

struct ContactField: View {
    let title: String
    @Binding var text: String
    let placeholder: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Field title
            Text(title)
                .font(.subheadline)
                .foregroundColor(.primary)

            // Input box
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(.gray)
                TextField(placeholder, text: $text)
                    .disableAutocorrection(true)
                    .foregroundColor(.primary)
            }
            .padding(.vertical, 8)     // ↓ slimmer
            .padding(.horizontal, 12)
            .frame(maxHeight:  50) // explicit max height
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.orange, lineWidth: 0.2)
                    .background(Color.white.cornerRadius(10))
            )
        }
    }
}

#if DEBUG
struct ContactField_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            ContactField(title: "Name (Optional)", text: .constant(""), placeholder: "Your name", icon: "person")
            ContactField(title: "Email (Optional)", text: .constant(""), placeholder: "you@example.com", icon: "envelope")
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }
}
#endif
