//
//  OnboardView.swift
//  splitr
//
//  Created by Christian Bryan Seputra on 20/07/26.
//
import SwiftUI

struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    var onGetStarted: (() -> Void)? = nil

    @State private var currentPage = 0

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


                // MARK: - Animation Slider

                TabView(selection: $currentPage) {
                    FloatingBillAnimation()
                        .frame(
                            width: 420,
                            height: 500
                        )
                        .tag(0)
                    
                    OnboardAnimation()
                        .frame(
                            width: 420,
                            height: 500
                        )
                        .tag(1)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: 500)


                Spacer()


                // MARK: - Text Content

                VStack(spacing: 12) {
                    if currentPage == 0 {
                        Text("Multiple Bills")
                            .font(
                                .system(
                                    size: 32,
                                    weight: .bold
                                )
                            )
                            .foregroundStyle(.black)
                            .transition(.asymmetric(insertion: .opacity, removal: .opacity))

                        Text(
                            "Add as many bills as you need and split\nevery expense with everyone involved."
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
                        .transition(.asymmetric(insertion: .opacity, removal: .opacity))
                    } else {
                        Text("Split Together")
                            .font(
                                .system(
                                    size: 32,
                                    weight: .bold
                                )
                            )
                            .foregroundStyle(.black)
                            .transition(.asymmetric(insertion: .opacity, removal: .opacity))

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
                        .transition(.asymmetric(insertion: .opacity, removal: .opacity))
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: currentPage)
                .frame(height: 110) // Fixed height to prevent vertical content shifting


                // MARK: - Slider Dots Indicator

                HStack(spacing: 8) {
                    ForEach(0..<2) { index in
                        Button {
                            withAnimation {
                                currentPage = index
                            }
                        } label: {
                            Capsule()
                                .fill(currentPage == index ? Color(red: 78/255, green: 124/255, blue: 247/255) : Color.black.opacity(0.1))
                                .frame(width: currentPage == index ? 20 : 8, height: 8)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: currentPage)
                .padding(.top, 20)


                // MARK: - Navigation Button

                Button {
                    if currentPage < 1 {
                        withAnimation {
                            currentPage += 1
                        }
                    } else {
                        hasCompletedOnboarding = true
                        onGetStarted?()
                    }
                } label: {

                    Text(currentPage == 1 ? "Get Started" : "Continue")
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
