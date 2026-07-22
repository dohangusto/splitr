//
//  PeopleCard.swift
//  splitr
//

import SwiftUI

struct PeopleCard: View {

    let people: [String]
    var onAddTapped: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {

            Text("People in this activity")
                .font(.headline)
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {

                    // Members are identified by an emoji avatar (an
                    // asset name may also appear) — render whichever
                    // the string resolves to.
                    ForEach(Array(people.enumerated()), id: \.offset) { _, person in
                        Group {
                            if let uiImage = UIImage(named: person) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                            } else {
                                Text(person)
                                    .font(.system(.title))
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .background(Color(.systemGray6))
                            }
                        }
                        .frame(width: 54, height: 54)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(Color(.systemGray5), lineWidth: 2)
                        )
                    }

                    // The "+" trails the newest avatar directly, scrolling
                    // with the row instead of pinning to the card's edge.
                    Button {
                        onAddTapped()
                    } label: {
                        Circle()
                            .fill(Color(.secondarySystemGroupedBackground))
                            .frame(width: 54, height: 54)
                            .overlay {
                                Circle()
                                    .stroke(Color(.systemGray5), lineWidth: 2)

                                Image(systemName: "plus")
                                    .font(.system(.title, weight: .regular))
                                    .foregroundStyle(.gray)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

#Preview {
    ZStack {
        Color("PrimaryBackground")
            .ignoresSafeArea()

        PeopleCard(
            people: [
                "avatar1",
                "avatar2",
                "avatar3",
                "avatar4",
                "avatar1",
                "avatar2"
            ]
        ) {
            print("Add tapped")
        }
        .padding(24)
    }
}
