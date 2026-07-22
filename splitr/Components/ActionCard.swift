//  ActionCard at HomePageView
//  Start a split or Join Split Room

import SwiftUI

struct ActionCard: View {
    let title: String
    let description: String
    let iconName: String
    let accentColor: Color
    let iconTintColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    Circle()
                        .fill(Color(.secondarySystemGroupedBackground))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: iconName)
                        .font(.system(.title3, weight: .bold))
                        .foregroundColor(iconTintColor)
                }
                .padding(.vertical,16)
                .padding(.leading, 12)
                
                
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .bold()
                        .foregroundColor(.white)
                    
                    Text(description)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                .padding([.leading, .bottom, .trailing],16)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 175)
            .background(accentColor)
            .cornerRadius(24)
            .shadow(color: accentColor.opacity(0.2), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(PlainButtonStyle())
    }
}
