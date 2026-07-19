//  TransactionRow at HomePageView
//  List of open transactions


import SwiftUI

struct TransactionRow: View {
    let roomName: String
    let membersCount: Int
    let billsCount: Int
    let actionLabel: String

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            ZStack {
                Circle()
                    .fill(Color(.systemGroupedBackground))
                    .frame(width: 44, height: 44)
                
                Image(systemName: "receipt.fill")
                    .font(.system(size: 18))
                    .foregroundColor(Color("SecondaryBlue"))
            }
            .padding(.leading, 20)
            
            // Text
            VStack(alignment: .leading, spacing: 2) {
                Text(roomName)
                    .font(.subheadline)
                    .bold()
                    .foregroundColor(.black)
                    .multilineTextAlignment(.leading)
                
                Text("\(membersCount) members, \(billsCount) bills")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Action Capsule
            HStack(spacing: 4) {
                Image(systemName: "hand.tap.fill")
                    .font(.system(size: 12))
                Text(actionLabel)
                    .font(.caption)
                    .bold()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color("SplitAirBlue").opacity(0.11))
            .foregroundColor(Color("SplitAirBlue"))
            .cornerRadius(12)
            
            // Chevron
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(.secondary.opacity(0.5))
                .padding(.trailing, 20)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}
