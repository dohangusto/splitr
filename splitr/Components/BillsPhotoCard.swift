//
//  BillsPhotoCard.swift
//  splitr
//

import SwiftUI

struct BillsPhotoCard: View {

    /// Receipt photos loaded from `ReceiptPhotoStore` (file-backed, not
    /// asset-catalog names).
    let photos: [UIImage]
    var onAddTapped: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {

            VStack(alignment: .leading, spacing: 4) {
                Text("Bills Photo")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text("Add more or edit bills photo")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 16) {

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {

                        ForEach(Array(photos.enumerated()), id: \.offset) { _, photo in
                            Image(uiImage: photo)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 90, height: 90)
                                .clipShape(
                                    RoundedRectangle(cornerRadius: 18)
                                )
                        }
                    }
                }

                Button {
                    onAddTapped()
                } label: {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color.white)
                        .frame(width: 90, height: 90)
                        .overlay {

                            RoundedRectangle(cornerRadius: 18)
                                .stroke(
                                    Color(.systemGray5),
                                    style: StrokeStyle(
                                        lineWidth: 2,
                                        dash: [8]
                                    )
                                )

                            Image(systemName: "plus")
                                .font(.system(size: 30))
                                .foregroundStyle(.gray)
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
    }
}

#Preview {
    ZStack {
        Color(red: 237/255, green: 242/255, blue: 255/255)
            .ignoresSafeArea()

        BillsPhotoCard(
            photos: ["receipt1", "receipt2"].compactMap { UIImage(named: $0) }
        ) {
            print("Tambah foto")
        }
        .padding(24)
    }
}
