//
//  DetailView.swift
//  splitr
//

import SwiftUI

struct DetailView: View {

    @State private var billName = ""

    @State private var people = [
        "avatar1",
        "avatar2",
        "avatar3",
        "avatar4"
    ]

    @State private var receiptPhotos = [
        "receipt1",
        "receipt2"
    ]

    var body: some View {
        ZStack {

            // MARK: Background
            Color(
                red: 237/255,
                green: 242/255,
                blue: 255/255
            )
            .ignoresSafeArea()

            // MARK: Content
            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {

                    // Header
                    NavigationHeader(title: "Detail")

                    // Split Bill Name
                    SplitBillNameCard(
                        billName: $billName
                    )

                    // People
                    PeopleCard(people: people) {
                        print("Tambah orang")
                    }

                    // Bills Photo
                    BillsPhotoCard(
                        photos: receiptPhotos
                    ) {
                        print("Tambah foto")
                    }

                    // Bill Detail
                    BillDetailCard()
                }
                .padding(20)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {

            // MARK: Sticky Bottom Button
            VStack {
                Button {
                    print("Confirmation tapped")
                } label: {
                    Text("Confirmation")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(
                            Color(
                                red: 82/255,
                                green: 126/255,
                                blue: 255/255
                            )
                        )
                        .clipShape(
                            Capsule()
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)
            .background(Color.white)
        }
        .navigationBarBackButtonHidden(true)
    }
}

#Preview {
    NavigationStack {
        DetailView()
    }
}
