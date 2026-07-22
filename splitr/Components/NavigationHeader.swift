//
//  NavigationHeader.swift
//  splitr
//
//  Created by Christian Bryan Seputra on 17/07/26.
//

import SwiftUI

struct NavigationHeader: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    var showBackButton: Bool = true

    var body: some View {
        ZStack {
            Text(title)
                .font(.system(.title2, weight: .semibold))
                .foregroundStyle(.primary)

            HStack {
                if showBackButton {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(.callout, weight: .medium))
                            .foregroundStyle(.primary)
                            .frame(width: 44, height: 44)
                            .background(Color(.secondarySystemGroupedBackground))
                            .clipShape(Circle())
                            .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
                    }
                }

                Spacer()
            }
        }
        .frame(minHeight: 54)
//        .padding(.horizontal, 24)
    }
}

#Preview {
    ZStack(alignment: .top) {
        Color("PrimaryBackground")
            .ignoresSafeArea()

        VStack {
            NavigationHeader(title: "Detail")
//                .padding(.top, 12)

            Spacer()
        }
    }
}
