//
//  TicketShape.swift
//  splitr
//
//  Created by Christian Bryan Seputra on 20/07/26.
//

import SwiftUI

struct TicketShape: Shape {
    var toothWidth: CGFloat = 24
    var toothHeight: CGFloat = 14

    func path(in rect: CGRect) -> Path {
        var path = Path()

        // MARK: - Top Zigzag
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))

        var x = rect.minX

        while x < rect.maxX {
            path.addLine(
                to: CGPoint(
                    x: min(x + toothWidth / 2, rect.maxX),
                    y: rect.minY + toothHeight
                )
            )

            path.addLine(
                to: CGPoint(
                    x: min(x + toothWidth, rect.maxX),
                    y: rect.minY
                )
            )

            x += toothWidth
        }

        // MARK: - Right Side
        path.addLine(
            to: CGPoint(
                x: rect.maxX,
                y: rect.maxY
            )
        )

        // MARK: - Bottom Zigzag
        x = rect.maxX

        while x > rect.minX {
            path.addLine(
                to: CGPoint(
                    x: max(x - toothWidth / 2, rect.minX),
                    y: rect.maxY - toothHeight
                )
            )

            path.addLine(
                to: CGPoint(
                    x: max(x - toothWidth, rect.minX),
                    y: rect.maxY
                )
            )

            x -= toothWidth
        }

        // MARK: - Left Side
        path.addLine(
            to: CGPoint(
                x: rect.minX,
                y: rect.minY
            )
        )

        path.closeSubpath()

        return path
    }
}


#Preview {
    NavigationStack {
        TicketShape()
    }
}
