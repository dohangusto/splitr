import SwiftUI

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

/// Presents a room's CKShare invitation URL for sending to friends.
struct ShareLinkSheet: View {
    let url: URL
    let roomName: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "person.2.wave.2")
                    .font(.largeTitle)
                    .foregroundStyle(.tint)
                Text("Invite friends to \(roomName)")
                    .font(.headline)
                Text("Anyone who opens this link joins the room and can claim their own items.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    ShareLink(item: url) {
                        Label("Send Invite Link", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
