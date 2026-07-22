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
    let onFinished: () -> Void

    var body: some View {
        VideoPlayer(player: player)
            .ignoresSafeArea()
            .onAppear {
                guard let url = Bundle.main.url(forResource: "successAnimation", withExtension: "mp4") else {
                    onFinished()
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
