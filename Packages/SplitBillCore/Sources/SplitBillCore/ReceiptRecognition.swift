import Foundation

/// A rectangle in normalized image coordinates: origin top-left, x right,
/// y down, all components in 0...1. Plain Doubles so Core stays free of
/// CoreGraphics/Vision types; the app layer converts from Vision's
/// bottom-left convention when adapting OCR output.
public struct NormalizedRect: Sendable, Hashable, Codable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }

    public func contains(x px: Double, y py: Double) -> Bool {
        px >= x && px <= maxX && py >= y && py <= maxY
    }

    /// Smallest rect covering both.
    public func union(_ other: NormalizedRect) -> NormalizedRect {
        let nx = Swift.min(x, other.x)
        let ny = Swift.min(y, other.y)
        return NormalizedRect(
            x: nx,
            y: ny,
            width: Swift.max(maxX, other.maxX) - nx,
            height: Swift.max(maxY, other.maxY) - ny
        )
    }
}

/// One piece of recognized text with its source geometry. This is the sole
/// currency between OCR (app layer) and parsing (Core): a visual line, or a
/// single table cell.
public struct RecognizedText: Sendable, Hashable, Codable {
    public var text: String
    /// Where the text sits in the receipt photo; nil for text-only input
    /// (manual fixtures, tests).
    public var box: NormalizedRect?
    /// OCR confidence 0...1; nil when unknown.
    public var confidence: Double?

    public init(text: String, box: NormalizedRect? = nil, confidence: Double? = nil) {
        self.text = text
        self.box = box
        self.confidence = confidence
    }
}

/// A receipt row as the parser consumes it: either a free-standing visual
/// line, or a structured table row (one entry per cell, left to right).
public enum ReceiptRow: Sendable, Hashable, Codable {
    case line(RecognizedText)
    case tableRow([RecognizedText])

    /// The row's text with cells joined, for keyword classification.
    public var joinedText: String {
        switch self {
        case .line(let text): return text.text
        case .tableRow(let cells):
            return cells.map(\.text).joined(separator: "  ")
        }
    }

    public var box: NormalizedRect? {
        switch self {
        case .line(let text): return text.box
        case .tableRow(let cells):
            let boxes = cells.compactMap(\.box)
            guard let first = boxes.first else { return nil }
            return boxes.dropFirst().reduce(first) { $0.union($1) }
        }
    }

    public var confidence: Double? {
        switch self {
        case .line(let text): return text.confidence
        case .tableRow(let cells): return cells.compactMap(\.confidence).min()
        }
    }
}

/// OCR output for one receipt photo, in reading order (top to bottom).
public struct RecognizedReceipt: Sendable, Hashable, Codable {
    public var rows: [ReceiptRow]

    public init(rows: [ReceiptRow]) {
        self.rows = rows
    }

    /// Builds the row sequence from free lines plus detected tables:
    /// lines whose center falls inside a table's region are dropped
    /// (the table's structured rows replace them), and table rows are
    /// spliced in at their vertical position.
    public init(lines: [RecognizedText], tables: [RecognizedTable]) {
        var entries: [(y: Double, row: ReceiptRow)] = []
        for line in lines {
            if let box = line.box,
               tables.contains(where: { table in
                   table.region?.contains(x: box.midX, y: box.midY) ?? false
               }) {
                continue
            }
            entries.append((line.box?.midY ?? Double(entries.count) * 0.001, .line(line)))
        }
        for table in tables {
            for cells in table.rows where !cells.isEmpty {
                let row = ReceiptRow.tableRow(cells)
                entries.append((row.box?.midY ?? table.region?.midY ?? 0, row))
            }
        }
        // Stable order: top to bottom (y grows downward).
        rows = entries.enumerated()
            .sorted { ($0.element.y, $0.offset) < ($1.element.y, $1.offset) }
            .map(\.element.row)
    }

    /// Groups recognized fragments into visual lines: receipts put the item
    /// name left and the amount right, and OCR often returns them as
    /// separate observations on the same row. Pure — unit-testable.
    public static func assembleLines(_ fragments: [RecognizedText]) -> [RecognizedText] {
        guard !fragments.isEmpty else { return [] }
        // Fragments without geometry can't be grouped; keep them as-is.
        guard fragments.allSatisfy({ $0.box != nil }) else { return fragments }
        // Top to bottom (y grows downward).
        let sorted = fragments.sorted { $0.box!.midY < $1.box!.midY }

        var lines: [[RecognizedText]] = []
        for fragment in sorted {
            if var current = lines.last,
               let anchor = current.first,
               abs(fragment.box!.midY - anchor.box!.midY)
                   < max(anchor.box!.height, fragment.box!.height) * 0.6 {
                current.append(fragment)
                lines[lines.count - 1] = current
            } else {
                lines.append([fragment])
            }
        }
        return lines.map { line in
            let ordered = line.sorted { $0.box!.x < $1.box!.x }
            return RecognizedText(
                text: ordered.map(\.text).joined(separator: "  "),
                box: ordered.dropFirst().reduce(ordered[0].box!) { $0.union($1.box!) },
                confidence: ordered.compactMap(\.confidence).min()
            )
        }
    }
}

/// A table detected in the receipt: rows of cells, left to right.
public struct RecognizedTable: Sendable, Hashable, Codable {
    public var rows: [[RecognizedText]]
    /// The table's overall region, used to deduplicate free lines that
    /// are really table content.
    public var region: NormalizedRect?

    public init(rows: [[RecognizedText]], region: NormalizedRect? = nil) {
        self.rows = rows
        self.region = region
    }
}
