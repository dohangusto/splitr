import SwiftUI
import UIKit

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

/// Native iOS system share sheet (UIActivityViewController) directly showing AirDrop, Messages, WhatsApp, Copy, etc.
struct ShareActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    let applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: applicationActivities
        )
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

/// Stand-in for direct iOS share sheet presentation with a URL
struct ShareLinkSheet: View {
    let url: URL
    var roomName: String = ""

    var body: some View {
        ShareActivityView(activityItems: [url])
    }
}
