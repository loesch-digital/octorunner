import AppKit
import DesignSystem
import SwiftUI

@MainActor
public enum RunnerMenuBarIcon {
    public static func image(for health: RunnerFleetHealth, differentiateWithoutColor: Bool = false) -> NSImage {
        let image = NSImage(size: NSSize(width: 32, height: 18), flipped: false) { _ in
            NSColor.labelColor.setStroke()
            NSColor.labelColor.setFill()
            drawLogo(in: NSRect(x: 10, y: -2, width: 22, height: 22))

            let color: NSColor
            switch health {
            case .unknown: color = .secondaryLabelColor
            case .healthy: color = NSColor(OctoTheme.onlineGreen)
            case .busy: color = NSColor(OctoTheme.accentBlue)
            case .offline: color = NSColor(OctoTheme.warningOrange)
            case .faulted: color = NSColor(OctoTheme.errorRed)
            }
            let indicatorBounds = NSRect(x: 1, y: 5, width: 8, height: 8)
            if differentiateWithoutColor {
                guard let symbol = NSImage(systemSymbolName: health.symbolName, accessibilityDescription: nil) else { return false }
                // Tint only the badge, preserving the neutral app mark.
                NSGraphicsContext.saveGraphicsState()
                indicatorBounds.clip()
                symbol.draw(in: indicatorBounds)
                color.setFill()
                indicatorBounds.fill(using: .sourceAtop)
                NSGraphicsContext.restoreGraphicsState()
            } else {
                let dot = NSBezierPath(ovalIn: indicatorBounds.insetBy(dx: 1, dy: 1))
                color.setFill()
                dot.fill()
                NSColor.labelColor.setStroke()
                dot.lineWidth = 0.5
                dot.stroke()
            }
            return true
        }
        // Preserve the badge color; the neutral logo follows the drawing appearance.
        image.isTemplate = false
        return image
    }

    /// Scalable vector geometry from docs/assets/menubar_icon.svg (24 × 24).
    private static func drawLogo(in rect: NSRect) {
        func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
            NSPoint(x: rect.minX + x * rect.width / 24, y: rect.maxY - y * rect.height / 24)
        }
        let loop = NSBezierPath()
        loop.move(to: point(18.178, 8))
        loop.curve(to: point(21.5, 12), controlPoint1: point(19.956, 8), controlPoint2: point(21.5, 9.567))
        loop.curve(to: point(18.178, 16), controlPoint1: point(21.5, 14.433), controlPoint2: point(19.956, 16))
        loop.curve(to: point(12, 11.156), controlPoint1: point(15.933, 16), controlPoint2: point(14.111, 13.911))
        loop.curve(to: point(5.822, 8), controlPoint1: point(9.889, 8.4), controlPoint2: point(8.067, 8))
        loop.curve(to: point(2.5, 12), controlPoint1: point(4.044, 8), controlPoint2: point(2.5, 9.567))
        loop.curve(to: point(5.822, 16), controlPoint1: point(2.5, 14.433), controlPoint2: point(4.044, 16))
        loop.curve(to: point(12, 11.156), controlPoint1: point(8.067, 16), controlPoint2: point(9.889, 13.911))
        loop.move(to: point(12, 12.844))
        loop.curve(to: point(18.178, 8), controlPoint1: point(14.111, 10.089), controlPoint2: point(15.933, 8))
        loop.lineWidth = 2 * rect.width / 24
        loop.lineCapStyle = .round
        loop.lineJoinStyle = .round
        loop.stroke()
        for x: CGFloat in [6.2, 17.8] {
            let center = point(x, 12)
            let radius = 1.6 * rect.width / 24
            NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)).fill()
        }
    }
}
