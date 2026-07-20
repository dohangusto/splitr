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

            HStack(spacing: 16) {

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {

                        ForEach(people, id: \.self) { person in
                            Image(person)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 54, height: 54)
                                .clipShape(Circle())
                                .overlay(
                                    Circle()
                                        .stroke(Color(.systemGray5), lineWidth: 2)
                                )
                        }
                    }
                }

                Button {
                    onAddTapped()
                } label: {
                    Circle()
                        .fill(.white)
                        .frame(width: 54, height: 54)
                        .overlay {
                            Circle()
                                .stroke(Color(.systemGray5), lineWidth: 2)

                            Image(systemName: "plus")
                                .font(.system(size: 28, weight: .regular))
                                .foregroundStyle(.gray)
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

#Preview {
    ZStack {
        Color(red: 237/255, green: 242/255, blue: 255/255)
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
