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
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(.black)

            HStack {
                if showBackButton {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.black)
                            .frame(width: 44, height: 44)
                            .background(Color.white)
                            .clipShape(Circle())
                            .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
                    }
                }

                Spacer()
            }
        }
        .frame(height: 54)
//        .padding(.horizontal, 24)
    }
}

#Preview {
    ZStack(alignment: .top) {
        Color(red: 240/255, green: 244/255, blue: 255/255)
            .ignoresSafeArea()

        VStack {
            NavigationHeader(title: "Detail")
//                .padding(.top, 12)

            Spacer()
        }
    }
}
