//  HistoryTransactionCard at HomePageView
//  List of Closed bill at History Tabview

import SwiftUI

struct HistoryTransactionCard: View {
    let roomName: String
    let membersCount: Int
    let billsCount: Int
    let statusLabel: String
 
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.15))
                    .frame(width: 48, height: 48)
 
                Image(systemName: "checkmark")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.green)
            }
 
            VStack(alignment: .leading, spacing: 4) {
                Text(roomName)
                    .font(.subheadline)
                    .bold()
                    .foregroundColor(.black)
 
                Text("\(membersCount) members, \(billsCount) bills")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
 
            Spacer(minLength: 8)
            
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12))
                Text(statusLabel)
                    .font(.caption)
                    .bold()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.gray.opacity(0.15))
            .foregroundColor(.gray)
            .cornerRadius(12)
 
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, minHeight: 110, idealHeight: 115, maxHeight: 120, alignment: .leading)
        .background(Color.white)
        .cornerRadius(24)
        .shadow(color: Color.black.opacity(0.04), radius: 10, x: 0, y: 5)
        .contentShape(Rectangle())
    }
}
