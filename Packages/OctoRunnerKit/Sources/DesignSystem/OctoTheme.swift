import AppKit
import CoreModels
import SwiftUI

public enum OctoTheme {
    // WCAG 2.2 Reference Surface RGB Tuples
    public static let darkSurfaceRGB: (Double, Double, Double) = (0.125, 0.125, 0.125)  // #202020
    public static let lightSurfaceRGB: (Double, Double, Double) = (0.965, 0.969, 0.976) // #F6F7F9

    // Adaptive Light & Dark Mode Surfaces (WCAG 2.2 AA/AAA Verified)
    public static let surfaceLowest = adaptiveColor(
        light: (0.945, 0.949, 0.961), // #F1F2F5
        dark: (0.055, 0.055, 0.055)   // #0E0E0E
    )
    public static let surfaceLow = adaptiveColor(
        light: (0.980, 0.984, 0.992), // #FAFBFD
        dark: (0.106, 0.106, 0.110)   // #1B1B1C
    )
    public static let surface = adaptiveColor(
        light: lightSurfaceRGB,       // #F6F7F9
        dark: darkSurfaceRGB          // #202020
    )
    public static let surfaceHigh = adaptiveColor(
        light: (0.910, 0.918, 0.937), // #E8EAEE
        dark: (0.165, 0.165, 0.165)   // #2A2A2A
    )
    public static let surfaceHighest = adaptiveColor(
        light: (0.867, 0.878, 0.902), // #DDE0E6
        dark: (0.208, 0.208, 0.208)   // #353535
    )

    // Semantic Colors (Adaptive High Contrast for Light & Dark Mode)
    public static let accentBlue = adaptiveColor(
        light: (0.0, 0.380, 0.820),   // #0061D1 (WCAG AA >= 4.5:1 on light surface)
        dark: (0.251, 0.612, 1.0)     // #409CFF (WCAG AA >= 4.5:1 on dark surface)
    )
    public static let onlineGreen = adaptiveColor(
        light: (0.086, 0.502, 0.220), // #168038 (WCAG AA >= 4.5:1 on light surface)
        dark: (0.204, 0.780, 0.349)   // #34C759
    )
    public static let warningOrange = adaptiveColor(
        light: (0.706, 0.365, 0.0),   // #B45D00
        dark: (1.0, 0.624, 0.039)     // #FF9F0A
    )
    public static let errorRed = adaptiveColor(
        light: (0.780, 0.110, 0.110), // #C71C1C
        dark: (1.0, 0.310, 0.270)     // #FF4F45
    )
    public static let outlineVariant = adaptiveColor(
        light: (0.680, 0.710, 0.765),
        dark: (0.255, 0.278, 0.333)
    )

    // Terminal Colors
    public static let terminalBackground = Color(red: 0.094, green: 0.094, blue: 0.094) // #181818
    public static let terminalForeground = Color(red: 0.890, green: 0.898, blue: 0.918) // #E3E5EA

    public static func statusColor(for status: RunnerStatus) -> Color {
        switch status {
        case .idle:
            onlineGreen
        case .busy:
            warningOrange
        case .offline:
            .secondary
        case .faulted:
            errorRed
        case .restarting:
            accentBlue
        }
    }

    // MARK: - W3C WCAG 2.2 Contrast Ratio Calculation

    public static func wcagRelativeLuminance(rgb: (Double, Double, Double)) -> Double {
        func channel(_ c: Double) -> Double {
            c <= 0.03928 ? (c / 12.92) : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(rgb.0) + 0.7152 * channel(rgb.1) + 0.0722 * channel(rgb.2)
    }

    public static func wcagContrastRatio(
        foregroundRGB: (Double, Double, Double),
        backgroundRGB: (Double, Double, Double)
    ) -> Double {
        let l1 = wcagRelativeLuminance(rgb: foregroundRGB)
        let l2 = wcagRelativeLuminance(rgb: backgroundRGB)
        let lighter = max(l1, l2)
        let darker = min(l1, l2)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private static func adaptiveColor(
        light: (Double, Double, Double),
        dark: (Double, Double, Double)
    ) -> Color {
        Color(
            nsColor: NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                let tuple = isDark ? dark : light
                return NSColor(srgbRed: tuple.0, green: tuple.1, blue: tuple.2, alpha: 1.0)
            }
        )
    }
}
