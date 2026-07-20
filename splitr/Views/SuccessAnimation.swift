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
    
    var body: some View {
        VideoPlayer(player: player)
            .ignoresSafeArea()
            .onAppear {
                guard let url = Bundle.main.url(forResource: "successAnimation", withExtension: "mp4") else {
                    return
                }
                player = AVPlayer(url: url)
                player?.play()
            }
    }
}

#Preview {
    SuccessAnimationView()
}
