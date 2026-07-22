import SwiftUI
import UIKit

struct SplashScreen: View {
    let onFinished: () -> Void

    // MARK: - Assets
    private let closedEye = "Icon1"
    private let openEye = "Icon2"

    // MARK: - States
    @State private var openEyeOpacity: Double = 0
    @State private var closedEyeOpacity: Double = 1

    @State private var scale: CGFloat = 0.55
    @State private var opacity: Double = 0
    @State private var logoOffset: CGFloat = 0
    @State private var rotation: Double = 0

    @State private var showTitle = false

    // Splash fade
    @State private var splashOpacity: Double = 1

    var body: some View {

        ZStack {
            ZStack {

                Color.white
                    .ignoresSafeArea()

                HStack(spacing: 12) {

                    ZStack {
                        Image(closedEye)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 88)
                            .opacity(closedEyeOpacity)
                            .animation(nil, value: closedEyeOpacity)

                        Image(openEye)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 88)
                            .opacity(openEyeOpacity)
                            .animation(nil, value: openEyeOpacity)
                    }
                    .scaleEffect(scale)
                    .rotationEffect(.degrees(rotation))
                    .offset(x: logoOffset)
                    .opacity(opacity)

                    if showTitle {

                        Text("Split Air")
                            .font(
                                .system(
                                    size: 34,
                                    weight: .bold,
                                    design: .rounded
                                )
                            )
                            .transition(
                                .move(edge: .trailing)
                                .combined(with: .opacity)
                            )
                    }
                }
            }
            .opacity(splashOpacity)
        }
        .task {
            await playAnimation()
        }
    }

    // MARK: Animation

    @MainActor
    func playAnimation() async {

        //----------------------------------------
        // Logo muncul
        //----------------------------------------

        withAnimation(
            .interactiveSpring(
                response: 0.7,
                dampingFraction: 0.82
            )
        ) {
            opacity = 1
            scale = 1
        }

        try? await Task.sleep(for: .milliseconds(650))

        //----------------------------------------
        // Blink 1
        //----------------------------------------

        openEyeOpacity = 1
        closedEyeOpacity = 0

        try? await Task.sleep(for: .milliseconds(150))

        openEyeOpacity = 0
        closedEyeOpacity = 1

        try? await Task.sleep(for: .milliseconds(120))

        openEyeOpacity = 1
        closedEyeOpacity = 0

        //----------------------------------------
        // Blink 2
        //----------------------------------------

        try? await Task.sleep(for: .milliseconds(260))

        openEyeOpacity = 0
        closedEyeOpacity = 1

        try? await Task.sleep(for: .milliseconds(90))

        openEyeOpacity = 1
        closedEyeOpacity = 0

        UIImpactFeedbackGenerator(style: .soft)
            .impactOccurred()

        //----------------------------------------
        // Bounce
        //----------------------------------------

        withAnimation(
            .spring(
                response: 0.28,
                dampingFraction: 0.42
            )
        ) {
            scale = 1.06
        }

        try? await Task.sleep(for: .milliseconds(170))

        withAnimation(
            .spring(
                response: 0.35,
                dampingFraction: 0.8
            )
        ) {
            scale = 1
        }

        //----------------------------------------
        // Jadi Brand
        //----------------------------------------

        try? await Task.sleep(for: .milliseconds(220))

        withAnimation(.linear(duration: 0.08)) {
            openEyeOpacity = 1
            closedEyeOpacity = 0
        }

        withAnimation(
            .interactiveSpring(
                response: 0.6,
                dampingFraction: 0.84
            )
        ) {
            scale = 0.68
            logoOffset = -18
            rotation = -4
        }

        try? await Task.sleep(for: .milliseconds(180))

        withAnimation(
            .spring(
                response: 0.3,
                dampingFraction: 0.8
            )
        ) {
            rotation = 0
        }

        withAnimation(.easeOut(duration: 0.45)) {
            showTitle = true
        }

        UIImpactFeedbackGenerator(style: .light)
            .impactOccurred()

        //----------------------------------------
        // User baca nama aplikasi
        //----------------------------------------

        try? await Task.sleep(for: .milliseconds(800))

        //----------------------------------------
        // Splash menghilang perlahan
        //----------------------------------------

        withAnimation(.easeInOut(duration: 0.45)) {
            splashOpacity = 0
        }

        try? await Task.sleep(for: .milliseconds(450))
        onFinished()
    }
}

#Preview {
    SplashScreen(onFinished: {})
}
