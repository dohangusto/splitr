//
//  OnboardView.swift
//  splitr
//
//  Created by Christian Bryan Seputra on 20/07/26.
//
import SwiftUI

struct OnboardingView: View {

    var body: some View {

        ZStack {

            LinearGradient(
                colors: [
                    Color(
                        red: 211 / 255,
                        green: 224 / 255,
                        blue: 254 / 255
                    ),
                    Color.white
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()


            // MARK: - Main Content

            VStack(spacing: 0) {

                Spacer()


                // MARK: - Animation

                OnboardAnimation()
                    .frame(
                        width: 420,
                        height: 420
                    )


                Spacer()


                // MARK: - Text Content

                VStack(spacing: 12) {

                    Text("Split Together")
                        .font(
                            .system(
                                size: 32,
                                weight: .bold
                            )
                        )
                        .foregroundStyle(.black)


                    Text(
                        "Join instantly with Nearby and split\nevery bill easily with your friends."
                    )
                    .font(
                        .system(
                            size: 17,
                            weight: .regular
                        )
                    )
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
                }


                // MARK: - Get Started Button

                Button {

                    // Navigate ke halaman berikutnya
                    // Tambahkan action di sini

                } label: {

                    Text("Get Started")
                        .font(
                            .system(
                                size: 17,
                                weight: .semibold
                            )
                        )
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(
                            LinearGradient(
                                colors: [
                                    Color(
                                        red: 112 / 255,
                                        green: 153 / 255,
                                        blue: 255 / 255
                                    ),
                                    Color(
                                        red: 78 / 255,
                                        green: 124 / 255,
                                        blue: 247 / 255
                                    )
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .clipShape(
                            Capsule()
                        )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 40)
                .padding(.top, 40)
                .padding(.bottom, 28)
            }
        }
    }
}


// MARK: - Preview

#Preview {

    OnboardingView()
}
