//
//  LoadingAnimation.swift
//  splitr
//
//  Created by Muhammad Husni Romdhoni on 20/07/26.
//

import SwiftUI
import ImageIO

class GIFUIImageView: UIImageView {
    var fixedSize: CGSize = .zero
    
    override var intrinsicContentSize: CGSize {
        fixedSize
    }
}

struct GIFImageView: UIViewRepresentable {
    let gifName: String
    let size: CGSize
    
    func makeUIView(context: Context) -> GIFUIImageView {
        let imageView = GIFUIImageView()
        imageView.fixedSize = size
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        loadGIF(into: imageView)
        return imageView
    }
    
    func updateUIView(_ uiView: GIFUIImageView, context: Context) {
        uiView.fixedSize = size
        uiView.invalidateIntrinsicContentSize()
    }
    
    private func loadGIF(into imageView: UIImageView) {
        guard let url = Bundle.main.url(forResource: gifName, withExtension: "gif"),
              let data = try? Data(contentsOf: url),
              let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return
        }
        
        let frameCount = CGImageSourceGetCount(source)
        var frames: [UIImage] = []
        var totalDuration: Double = 0
        
        for i in 0..<frameCount {
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }
            frames.append(UIImage(cgImage: cgImage))
            
            let properties = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [String: Any]
            let gifInfo = properties?[kCGImagePropertyGIFDictionary as String] as? [String: Any]
            let delay = gifInfo?[kCGImagePropertyGIFUnclampedDelayTime as String] as? Double ?? 0.1
            totalDuration += delay
        }
        
        imageView.animationImages = frames
        imageView.animationDuration = totalDuration
        imageView.animationRepeatCount = 0
        imageView.startAnimating()
    }
}

struct LoadingAnimationView: View {
    var body: some View {
        GIFImageView(gifName: "loadingAnimation", size: CGSize(width: 100, height: 100))
            .frame(width: 100, height: 100)
    }
}

#Preview {
    LoadingAnimationView()
}
