import SwiftUI
import UIKit

/// Local-only persistence for receipt photos, keyed by `Bill.photoReference`.
/// Photos never sync to CloudKit — members work from the reviewed line
/// items; the photo is a host-side verification aid while editing.
enum ReceiptPhotoStore {
    private static var directory: URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0].appendingPathComponent("ReceiptPhotos", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    /// Saves as JPEG and returns the reference to store on the Bill.
    static func save(_ image: UIImage) -> String? {
        guard let data = image.jpegData(compressionQuality: 0.7) else { return nil }
        let reference = "\(UUID().uuidString).jpg"
        do {
            try data.write(to: directory.appendingPathComponent(reference))
            return reference
        } catch {
            return nil
        }
    }

    static func load(_ reference: String?) -> UIImage? {
        guard let reference else { return nil }
        return UIImage(contentsOfFile: directory.appendingPathComponent(reference).path)
    }

    static func loadData(_ reference: String?) -> Data? {
        guard let reference else { return nil }
        return try? Data(contentsOf: directory.appendingPathComponent(reference))
    }

    static func saveData(_ data: Data, reference: String) {
        let fileURL = directory.appendingPathComponent(reference)
        try? data.write(to: fileURL)
    }

    static func delete(_ reference: String?) {
        guard let reference else { return }
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(reference))
    }
}

/// The receipt photo pinned above the bill form: always in view while
/// editing (no round-tripping to a separate screen), pinch-to-zoom and pan
/// to read small print, collapsible when the user needs the room.
struct ReceiptPhotoPane: View {
    let image: UIImage

    @State private var isCollapsed = false
    @State private var zoom: CGFloat = 1
    @State private var steadyZoom: CGFloat = 1

    private let paneHeight: CGFloat = 240

    var body: some View {
        VStack(spacing: 0) {
            header
            if !isCollapsed {
                zoomableImage
                    .frame(height: paneHeight)
                    .clipped()
            }
            Divider()
        }
        .background(.thinMaterial)
    }

    private var header: some View {
        Button {
            withAnimation(.snappy) { isCollapsed.toggle() }
        } label: {
            HStack {
                Label("Receipt photo", systemImage: "doc.viewfinder")
                    .font(.footnote.weight(.medium))
                Spacer()
                if !isCollapsed, zoom > 1.01 {
                    Text("\(zoom, format: .number.precision(.fractionLength(1)))×")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .rotationEffect(.degrees(isCollapsed ? -90 : 0))
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .accessibilityLabel(isCollapsed ? "Show receipt photo" : "Hide receipt photo")
    }

    private var zoomableImage: some View {
        GeometryReader { proxy in
            ScrollView([.horizontal, .vertical], showsIndicators: false) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(
                        width: max(proxy.size.width, proxy.size.width * zoom),
                        height: imageHeight(fitting: proxy.size) * zoom
                    )
            }
            .defaultScrollAnchor(.center)
        }
        .gesture(
            MagnifyGesture()
                .onChanged { value in
                    zoom = min(max(steadyZoom * value.magnification, 1), 6)
                }
                .onEnded { _ in
                    steadyZoom = zoom
                }
        )
        .onTapGesture(count: 2) {
            withAnimation(.snappy) {
                zoom = zoom > 1.01 ? 1 : 2.5
                steadyZoom = zoom
            }
        }
    }

    private func imageHeight(fitting size: CGSize) -> CGFloat {
        guard image.size.width > 0 else { return size.height }
        return size.width * image.size.height / image.size.width
    }
}
