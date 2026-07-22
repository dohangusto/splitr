//
//  OnboardAnimation.swift
//  splitr
//

import SwiftUI

struct OnboardAnimation: View {

    // MARK: - Main Animation States

    @State private var isBlinking = false
    @State private var isPulsing = false
    @State private var startOrbiting = false

    // Entrance States
    @State private var showIcon = false
    @State private var showInnerCircle = false
    @State private var showOuterCircle = false
    @State private var visibleAvatarCount = 0


    // MARK: - Avatar Configuration

    private let avatars = [

        // Circle 2 (Radius 170) - Purple Dumpling
        OrbitAvatarData(
            imageName: "Avatar1",
            radius: 170,
            duration: 26,
            startAngle: 90,
            clockwise: false
        ),

        // Circle 2 (Radius 170) - Orange Head
        OrbitAvatarData(
            imageName: "Avatar2",
            radius: 170,
            duration: 26,
            startAngle: 210,
            clockwise: false
        ),

        // Circle 1 (Radius 100) - Green Worm
        OrbitAvatarData(
            imageName: "Avatar3",
            radius: 100,
            duration: 18,
            startAngle: 30,
            clockwise: true
        ),

        // Circle 1 (Radius 100) - Pink Flower
        OrbitAvatarData(
            imageName: "Avatar4",
            radius: 100,
            duration: 18,
            startAngle: 210,
            clockwise: true
        ),

        // Circle 2 (Radius 170) - Red Spiky
        OrbitAvatarData(
            imageName: "Avatar5",
            radius: 170,
            duration: 26,
            startAngle: 330,
            clockwise: false
        )
    ]


    // MARK: - Body

    var body: some View {

        ZStack {

            // MARK: - Concentric Orbit Circles (Background)

            // Circle 1 (Inner, size 200)
            PulsingOrbitCircle(
                size: 200,
                baseOpacity: 0.08,
                pulseOpacity: 0.16,
                scaleAmount: 1.025,
                duration: 2.8,
                delay: 0,
                isVisible: showInnerCircle
            )

            // Circle 2 (Outer, size 340)
            PulsingOrbitCircle(
                size: 340,
                baseOpacity: 0.06,
                pulseOpacity: 0.12,
                scaleAmount: 1.01,
                duration: 3.4,
                delay: 0.4,
                isVisible: showOuterCircle
            )


            // MARK: - Orbiting Avatars

            ForEach(
                Array(avatars.enumerated()),
                id: \.element.id
            ) { index, avatar in

                OrbitingAvatar(
                    data: avatar,
                    isVisible: index < visibleAvatarCount,
                    isOrbiting: startOrbiting
                )
            }


            // MARK: - Center Mascot Glow

            Circle()
                .fill(
                    Color.blue.opacity(
                        isPulsing
                            ? 0.08
                            : 0.03
                    )
                )
                .frame(
                    width: 110,
                    height: 110
                )
                .scaleEffect(
                    showIcon
                        ? (isPulsing ? 1.12 : 1.0)
                        : 0.3
                )
                .opacity(
                    showIcon ? 1 : 0
                )
                .blur(radius: 10)
                .animation(
                    .easeInOut(duration: 2)
                        .repeatForever(
                            autoreverses: true
                        ),
                    value: isPulsing
                )


            // MARK: - Center App Icon

            Image(
                isBlinking
                    ? "Icon2"
                    : "Icon1"
            )
            .resizable()
            .scaledToFit()
            .frame(
                width: 65,
                height: 65
            )
            .scaleEffect(
                showIcon
                    ? (isPulsing ? 1.02 : 1.0)
                    : 0.3
            )
            .opacity(
                showIcon ? 1 : 0
            )
            .zIndex(10)
        }
        .frame(
            width: 420,
            height: 420
        )


        // MARK: - Entrance Animation

        .task {

            await playEntranceAnimation()

            // Mulai pulse setelah entrance
            isPulsing = true

            // Mulai avatar mengorbit
            startOrbiting = true
        }


        // MARK: - Blink Animation

        .task {

            // Tunggu entrance icon
            try? await Task.sleep(
                for: .seconds(1.5)
            )

            while !Task.isCancelled {
                // Mata terbuka (stay phase)
                isBlinking = false
                try? await Task.sleep(for: .seconds(2.5))

                // Kedip 1 (mata tertutup)
                isBlinking = true
                try? await Task.sleep(for: .seconds(0.12))

                // Buka mata sebentar
                isBlinking = false
                try? await Task.sleep(for: .seconds(0.12))

                // Kedip 2 (mata tertutup)
                isBlinking = true
                try? await Task.sleep(for: .seconds(0.12))

                // Mata terbuka kembali
                isBlinking = false
            }
        }
    }


    // MARK: - Play Entrance Animation

    @MainActor
    private func playEntranceAnimation() async {

        // Reset
        showIcon = false
        showInnerCircle = false
        showOuterCircle = false
        visibleAvatarCount = 0
        startOrbiting = false


        // MARK: 1. Center Icon Pop

        try? await Task.sleep(
            for: .seconds(0.15)
        )

        withAnimation(
            .spring(
                response: 0.55,
                dampingFraction: 0.68
            )
        ) {
            showIcon = true
        }


        // MARK: 2. Inner Circle

        try? await Task.sleep(
            for: .seconds(0.3)
        )

        withAnimation(
            .easeOut(
                duration: 0.65
            )
        ) {
            showInnerCircle = true
        }


        // MARK: 3. Outer Circle

        try? await Task.sleep(
            for: .seconds(0.25)
        )

        withAnimation(
            .easeOut(
                duration: 0.75
            )
        ) {
            showOuterCircle = true
        }


        // MARK: 4. Avatar 1

        try? await Task.sleep(
            for: .seconds(0.25)
        )

        withAnimation(
            .spring(
                response: 0.45,
                dampingFraction: 0.65
            )
        ) {
            visibleAvatarCount = 1
        }


        // MARK: 5. Avatar 2

        try? await Task.sleep(
            for: .seconds(0.15)
        )

        withAnimation(
            .spring(
                response: 0.45,
                dampingFraction: 0.65
            )
        ) {
            visibleAvatarCount = 2
        }


        // MARK: 6. Avatar 3

        try? await Task.sleep(
            for: .seconds(0.15)
        )

        withAnimation(
            .spring(
                response: 0.45,
                dampingFraction: 0.65
            )
        ) {
            visibleAvatarCount = 3
        }


        // MARK: 7. Avatar 4

        try? await Task.sleep(
            for: .seconds(0.15)
        )

        withAnimation(
            .spring(
                response: 0.45,
                dampingFraction: 0.65
            )
        ) {
            visibleAvatarCount = 4
        }


        // MARK: 8. Avatar 5

        try? await Task.sleep(
            for: .seconds(0.15)
        )

        withAnimation(
            .spring(
                response: 0.45,
                dampingFraction: 0.65
            )
        ) {
            visibleAvatarCount = 5
        }


        // Tunggu semua avatar selesai pop
        try? await Task.sleep(
            for: .seconds(0.5)
        )
    }
}


// MARK: - Pulsing Orbit Circle

private struct PulsingOrbitCircle: View {

    let size: CGFloat

    let baseOpacity: Double
    let pulseOpacity: Double

    let scaleAmount: CGFloat

    let duration: Double
    let delay: Double

    let isVisible: Bool


    @State private var animate = false
    @State private var rotation: Double = 0
    @State private var strokeTrim: CGFloat = 0


    var body: some View {

        ZStack {
            
            // Base Circle (always visible, pulsing in opacity/scale)
            Circle()
                .trim(from: 0, to: strokeTrim)
                .stroke(
                    Color.blue.opacity(
                        animate
                            ? pulseOpacity
                            : baseOpacity
                    ),
                    lineWidth: 1
                )
            
            // Glowing sweep overlay (sweeps around with rotation effect)
            Circle()
                .trim(from: 0, to: strokeTrim)
                .stroke(
                    AngularGradient(
                        colors: [
                            .clear,
                            Color.blue.opacity(0.05),
                            Color(red: 160/255, green: 200/255, blue: 255/255).opacity(0.3),
                            Color.white.opacity(0.9), // Bright shine point
                            Color(red: 160/255, green: 200/255, blue: 255/255).opacity(0.3),
                            Color.blue.opacity(0.05),
                            .clear
                        ],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
                )
                .rotationEffect(.degrees(rotation))
                .blur(radius: 0.5)
        }
        .frame(
            width: size,
            height: size
        )

        // Circle muncul dari tengah
        .scaleEffect(
            isVisible
                ? (animate ? scaleAmount : 1)
                : 0.3
        )

        .opacity(
            isVisible
                ? 1.0
                : 0
        )

        .onChange(
            of: isVisible
        ) { _, newValue in

            if newValue {

                // 1. Entrance trim animation
                withAnimation(
                    .easeOut(
                        duration: 1.4
                    )
                    .delay(delay)
                ) {
                    strokeTrim = 1.0
                }

                // 2. Pulse scale and opacity animation (loops forever)
                withAnimation(
                    .easeInOut(
                        duration: duration
                    )
                    .delay(delay + 1.4)
                    .repeatForever(
                        autoreverses: true
                    )
                ) {
                    animate = true
                }

                // 3. Continuous rotation for the sweep/shine effect (loops forever)
                withAnimation(
                    .linear(
                        duration: 5.5
                    )
                    .delay(delay)
                    .repeatForever(
                        autoreverses: false
                    )
                ) {
                    rotation = 360
                }
            }
        }
    }
}


// MARK: - Orbit Avatar Data

private struct OrbitAvatarData: Identifiable {

    let id = UUID()

    let imageName: String

    let radius: CGFloat

    let duration: Double

    let startAngle: Double

    let clockwise: Bool
}


// MARK: - Orbiting Avatar

private struct OrbitingAvatar: View {

    let data: OrbitAvatarData

    let isVisible: Bool
    let isOrbiting: Bool

    @State private var startTime: Double = 0


    var body: some View {

        TimelineView(.animation) { timeline in

            // MARK: - Time

            let time =
                timeline.date
                    .timeIntervalSinceReferenceDate


            // MARK: - Progress

            let elapsed = isOrbiting ? max(0, time - startTime) : 0

            let progress =
                elapsed
                    .truncatingRemainder(
                        dividingBy: data.duration
                    )
                / data.duration


            // MARK: - Direction

            let direction =
                data.clockwise
                    ? 1.0
                    : -1.0


            // MARK: - Angle

            let animatedAngle =
                progress
                * 360
                * direction


            let currentAngle =
                data.startAngle
                + animatedAngle


            let radians =
                currentAngle
                * .pi
                / 180


            // MARK: - Avatar

            Image(data.imageName)
                .resizable()
                .scaledToFit()
                .frame(
                    width: 48,
                    height: 48
                )

                // Posisi pada orbit
                .offset(
                    x: cos(radians)
                        * data.radius,

                    y: sin(radians)
                        * data.radius
                )

                // Gentle Pop
                .scaleEffect(
                    isVisible
                        ? 1
                        : 0.15
                )

                .opacity(
                    isVisible
                        ? 1
                        : 0
                )
        }
        .onChange(of: isOrbiting, initial: true) { oldValue, newValue in
            if newValue {
                startTime = Date().timeIntervalSinceReferenceDate
            }
        }
    }
}


// MARK: - Preview

#Preview {

    ZStack {

        LinearGradient(
            colors: [
                Color(
                    red: 211 / 255,
                    green: 224 / 255,
                    blue: 254 / 255
                ),

                Color(
                    red: 240 / 255,
                    green: 244 / 255,
                    blue: 255 / 255
                )
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()


        OnboardAnimation()
    }
}
