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
            
            HStack(spacing: 14) {
                Image("LaunchLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 50, height: 50)
                
                Text("Welcome to NEMA USA!")
                    .font(.system(size: 23, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            }
            .padding(.vertical, 12)
            .padding(.horizontal)
        }
        .frame(height: 56)
    }
}

