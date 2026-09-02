//
//  SuccessAnimation.swift
//  splitr
//
//  Created by Muhammad Husni Romdhoni on 20/07/26.
//

import SwiftUI
import AVKit

struct SuccessAnimationView: View {
    @State private var player: AVPlayer?
    @State private var useFallbackAnimation = false
    @State private var checkmarkProgress: CGFloat = 0
    @State private var circleScale: CGFloat = 0.5
    @State private var circleOpacity: Double = 0
    let onFinished: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if useFallbackAnimation {
                VStack(spacing: 24) {
                    ZStack {
                        Circle()
                            .stroke(Color.green.opacity(0.2), lineWidth: 4)
                            .frame(width: 100, height: 100)

                        Circle()
                            .trim(from: 0, to: checkmarkProgress)
                            .stroke(Color.green, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                            .frame(width: 100, height: 100)
                            .rotationEffect(.degrees(-90))

                        Image(systemName: "checkmark")
                            .font(.system(size: 44, weight: .bold))
                            .foregroundColor(.green)
                            .scaleEffect(circleScale)
                            .opacity(circleOpacity)
                    }
                    .frame(width: 120, height: 120)

                    Text("Payment Marked as Paid!")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                        .opacity(circleOpacity)
                }
                .onAppear {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.6, blendDuration: 0)) {
                        circleScale = 1.0
                        circleOpacity = 1.0
                    }
                    withAnimation(.easeInOut(duration: 0.8).delay(0.2)) {
                        checkmarkProgress = 1.0
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                        onFinished()
                    }
                }
            } else {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            }
        }
        .onAppear {
            guard let url = Bundle.main.url(forResource: "successAnimation", withExtension: "mp4") else {
                useFallbackAnimation = true
                return
            }
            let player = AVPlayer(url: url)
            self.player = player

            NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: player.currentItem,
                queue: .main
            ) { _ in
                onFinished()
            }

            player.play()
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }
}

#Preview {
    SuccessAnimationView(onFinished: {})
}
