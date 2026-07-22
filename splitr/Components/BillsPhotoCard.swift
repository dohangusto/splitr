//
//  BillsPhotoCard.swift
//  splitr
//

import SplitBillCore
import SwiftUI

struct BillsPhotoCard: View {

    /// The list of bills in the room. We extract photos that exist.
    let bills: [Bill]
    var onAddTapped: () -> Void = {}
    var onPhotoTapped: (Bill, UIImage) -> Void = { _, _ in }

    private struct DisplayPhoto: Identifiable {
        let id: UUID
        let bill: Bill
        let image: UIImage
    }

    private var displayPhotos: [DisplayPhoto] {
        bills.compactMap { bill in
            guard let ref = bill.photoReference else { return nil }
            let image = ReceiptPhotoStore.load(ref) ?? UIImage(named: ref)
            guard let image else { return nil }
            return DisplayPhoto(id: bill.id, bill: bill, image: image)
        }
    }

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

                        ForEach(displayPhotos) { item in
                            Button {
                                onPhotoTapped(item.bill, item.image)
                            } label: {
                                Image(uiImage: item.image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 90, height: 90)
                                    .clipShape(
                                        RoundedRectangle(cornerRadius: 18)
                                    )
                            }
                            .buttonStyle(.plain)
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
            bills: MockData.rooms()[0].bills
        ) {
            print("Tambah foto")
        }
        .padding(24)
    }
}
