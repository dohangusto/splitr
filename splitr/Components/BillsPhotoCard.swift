//
//  BillsPhotoCard.swift
//  splitr
//

import SwiftUI

struct BillsPhotoCard: View {

    /// Receipt photos loaded from `ReceiptPhotoStore` (file-backed, not
    /// asset-catalog names).
    let photos: [UIImage]
    /// The "+" is only present while the bill set is still open for changes
    /// (the room is `.open`). Once claiming starts, the receipts are fixed.
    var showsAddButton: Bool = true
    var onAddTapped: () -> Void = {}
    /// Tapping a thumbnail opens it for a closer look.
    var onPhotoTapped: (UIImage) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {

            VStack(alignment: .leading, spacing: 4) {
                Text("Bills Photo")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(showsAddButton ? "Add more or edit bills photo" : "Tap a photo to view it")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {

                    ForEach(Array(photos.enumerated()), id: \.offset) { _, photo in
                        Button {
                            onPhotoTapped(photo)
                        } label: {
                            Image(uiImage: photo)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 90, height: 90)
                                .clipShape(
                                    RoundedRectangle(cornerRadius: 18)
                                )
                        }
                        .buttonStyle(.plain)
                    }

                    // The "+" trails the newest photo directly, scrolling
                    // with the row instead of pinning to the card's edge.
                    if showsAddButton {
                        Button {
                            onAddTapped()
                        } label: {
                            RoundedRectangle(cornerRadius: 18)
                                .fill(Color(.secondarySystemGroupedBackground))
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
                                        .font(.system(.title))
                                        .foregroundStyle(.gray)
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
    }
}

#Preview {
    ZStack {
        Color("PrimaryBackground")
            .ignoresSafeArea()

        BillsPhotoCard(
            photos: ["receipt1", "receipt2"].compactMap { UIImage(named: $0) }
        ) {
            print("Tambah foto")
        }
        .padding(24)
    }
}
