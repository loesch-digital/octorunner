import AppKit
import DesignSystem
import SwiftUI

@MainActor
public enum RunnerMenuBarIcon {
    public static func image(for health: RunnerFleetHealth) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { bounds in
            guard let symbol = NSImage(systemSymbolName: health.symbolName, accessibilityDescription: nil) else { return false }
            symbol.draw(in: bounds)
            let color: NSColor
            switch health {
            case .unknown: color = .secondaryLabelColor
            case .healthy: color = NSColor(OctoTheme.onlineGreen)
            case .busy: color = NSColor(OctoTheme.accentBlue)
            case .offline: color = NSColor(OctoTheme.warningOrange)
            case .faulted: color = NSColor(OctoTheme.errorRed)
            }
            color.setFill()
            bounds.fill(using: .sourceAtop)
            return true
        }
        // A template image would discard the health color in the system menu bar.
        image.isTemplate = false
        return image
    }
}
