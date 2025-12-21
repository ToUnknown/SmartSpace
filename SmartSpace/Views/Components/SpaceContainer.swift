//
//  SpaceContainer.swift
//  SmartSpace
//
//  Created by Максим Гайдук on 11.11.2025.
//

import SwiftUI

struct SpaceContainer: View {
    var body: some View {
        HStack {
            Image(.example)
                .resizable()
                .scaledToFit()
                .frame(height: .infinity)
                .cornerRadius(15)
                .shadow(radius: 10)
                .padding(.trailing, 10)
            
            VStack(alignment: .leading) {
                //Space name
                Text("Sace Name")
                    .font(.title2)
                    .fontWeight(.bold)
                
                //Space type
                Text("Space Type")
                .font(.subheadline)
                .fontWeight(.semibold)
                .padding(.horizontal, 13)
                .padding(.vertical, 5)
                .background(.yellow)
                .clipShape(.capsule)
            }
            Spacer()
        }
        .frame(width: .infinity, height: 90)
    }
}
