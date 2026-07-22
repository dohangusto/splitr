//
//  FloatingBillAnimation.swift
//  splitr
//

import SwiftUI

struct FloatingBillAnimation: View {

    @State private var showPhone = false
    @State private var showCard = false
    @State private var floating = false

    var body: some View {

        ZStack {

            // MARK: - Background Circle Shine
            CircleShineBackground()
                .allowsHitTesting(false)

            // MARK: Phone

            Image("hp")
                .resizable()
                .scaledToFit()
                .frame(width: 240)

                .offset(
                    y: showPhone ? 40 : 250
                )

                .opacity(
                    showPhone ? 1 : 0
                )

                .scaleEffect(
                    floating ? 1.01 : 1
                )

                .rotationEffect(
                    .degrees(
                        floating ? -0.6 : 0.6
                    )
                )

                .animation(
                    .easeInOut(duration: 2.2)
                        .repeatForever(
                            autoreverses: true
                        ),
                    value: floating
                )


            // MARK: Floating Bill Card

            Image("billcard")
                .resizable()
                .scaledToFit()
                .frame(width: 320)

            .offset(
                y: showCard ? 70 : 120
            )

            .opacity(
                showCard ? 1 : 0
            )

            .scaleEffect(
                showCard ? 1 : 0.85
            )

            .offset(
                y: floating ? -8 : 8
            )

            .rotationEffect(
                .degrees(
                    floating ? 1 : -1
                )
            )

            .animation(
                .easeInOut(duration: 2)
                    .repeatForever(
                        autoreverses: true
                    ),
                value: floating
            )
        }
        .frame(width: 420, height: 500)

        .task {

            // Phone masuk

            withAnimation(
                .spring(
                    response: 0.75,
                    dampingFraction: 0.82
                )
            ) {
                showPhone = true
            }

            try? await Task.sleep(
                for: .seconds(0.45)
            )

            // Card muncul

            withAnimation(
                .spring(
                    response: 0.6,
                    dampingFraction: 0.8
                )
            ) {
                showCard = true
            }

            try? await Task.sleep(
                for: .seconds(0.25)
            )

            floating = true
        }
    }
}


// MARK: Receipt Card

private struct ReceiptCard: View {

    let image: String

    var body: some View {

        Image(image)
            .resizable()
            .scaledToFill()
            .frame(width: 72, height: 100)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 16
                )
            )
    }
}


// MARK: Add Card

private struct AddCard: View {

    var body: some View {

        RoundedRectangle(cornerRadius: 16)
            .fill(Color(.systemGray6))
            .frame(width: 72, height: 100)
            .overlay {

                Image(systemName: "plus")
                    .font(.title2)
                    .foregroundStyle(.gray)
            }
    }
}
// MARK: - Floating Effect Modifier

private struct FloatingEffect: ViewModifier {

    let active: Bool

    func body(content: Content) -> some View {

        content
            .offset(
                y: active ? -6 : 6
            )
            .animation(
                .easeInOut(duration: 2.2)
                    .repeatForever(
                        autoreverses: true
                    ),
                value: active
            )
    }
}

extension View {

    func floating(_ active: Bool) -> some View {
        modifier(
            FloatingEffect(
                active: active
            )
        )
    }
}

// MARK: - Preview

#Preview {

    ZStack {

        LinearGradient(
            colors: [
                Color(
                    red: 0.84,
                    green: 0.90,
                    blue: 1.0
                ),
                Color.white
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()

        FloatingBillAnimation()
    }
}

// MARK: - Background Circle Shine

struct CircleShineBackground: View {
    @State private var rotation: Double = 0.0
    @State private var scale: CGFloat = 1.0
    
    private let buttonBlue = Color("SplitAirBlue")
    
    var body: some View {
        ZStack {
            // Outer Circle (Muted to blend smoothly with bg)
            Circle()
                .stroke(
                    buttonBlue.opacity(0.18),
                    lineWidth: 3.0
                )
                .frame(width: 320, height: 320)
            
            // Outer Circle Shine Glow Overlay (Bright blue & white with no dark clear bands)
            Circle()
                .stroke(
                    AngularGradient(
                        colors: [buttonBlue.opacity(0), buttonBlue.opacity(0.4), .white, buttonBlue.opacity(0.4), buttonBlue.opacity(0)],
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360)
                    ),
                    lineWidth: 4.0
                )
                .frame(width: 320, height: 320)
                .rotationEffect(.degrees(rotation))
                .blur(radius: 0.5)
            
            // Inner Circle (Muted to blend smoothly with bg)
            Circle()
                .stroke(
                    buttonBlue.opacity(0.12),
                    lineWidth: 2.0
                )
                .frame(width: 200, height: 200)
            
            // Inner Circle Shine Glow Overlay (opposing spin)
            Circle()
                .stroke(
                    AngularGradient(
                        colors: [buttonBlue.opacity(0), buttonBlue.opacity(0.4), .white, buttonBlue.opacity(0.4), buttonBlue.opacity(0)],
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360)
                    ),
                    lineWidth: 3.0
                )
                .frame(width: 200, height: 200)
                .rotationEffect(.degrees(-rotation * 0.8))
                .blur(radius: 0.5)
        }
        .scaleEffect(scale)
        .onAppear {
            // Continuously rotate the shine point
            withAnimation(.linear(duration: 6.0).repeatForever(autoreverses: false)) {
                rotation = 360
            }
            // Subtle breathing pulse
            withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true)) {
                scale = 1.03
            }
        }
    }
}
