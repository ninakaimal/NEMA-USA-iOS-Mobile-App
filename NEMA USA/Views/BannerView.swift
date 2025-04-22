//
//  BannerView.swift
//  NEMA USA
//  Created by Nina on 4/15/25.

import SwiftUI

struct BannerView: View {
    var body: some View {
        ZStack(alignment: .leading) {
            // Orange wedge fills the top safe area
            Color.orange
                .ignoresSafeArea(edges: .top)
            
            HStack(spacing: 12) {
                Image("LaunchLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 44, height: 44)
                
                Text("Welcome to NEMA USA!")
                    .font(.title2).bold()
                    .foregroundColor(.white)
                
                Spacer()
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 56)
    }
}

