
//
//  SplitBillNameCard.swift
//  splitr
//

import SwiftUI

struct SplitBillNameCard: View {

    @Binding var billName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            Text("Bills name")
                .font(.headline)
                .foregroundStyle(.secondary)

            TextField("Masukkan nama split bill", text: $billName)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.black)
                .textFieldStyle(.plain)

            Rectangle()
                .fill(Color.gray.opacity(0.6))
                .frame(height: 1)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

#Preview {

    @Previewable @State var billName = "Mie Gacoan Jogja"

    ZStack {
        Color(red: 237/255, green: 242/255, blue: 255/255)
            .ignoresSafeArea()

        SplitBillNameCard(billName: $billName)
            .padding(24)
    }
}
