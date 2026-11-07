import CoreModels
import SwiftUI

public enum OctoTheme {
    // Dark Mode Base Surfaces (from 02-design-system-and-hig.md)
    public static let surfaceLowest = Color(red: 0.055, green: 0.055, blue: 0.055) // #0E0E0E
    public static let surfaceLow = Color(red: 0.106, green: 0.106, blue: 0.110)    // #1B1B1C
    public static let surface = Color(red: 0.125, green: 0.125, blue: 0.125)       // #202020
    public static let surfaceHigh = Color(red: 0.165, green: 0.165, blue: 0.165)   // #2A2A2A
    public static let surfaceHighest = Color(red: 0.208, green: 0.208, blue: 0.208)// #353535

    // Semantic Colors
    public static let accentBlue = Color(red: 0.0, green: 0.478, blue: 1.0)        // #007AFF
    public static let onlineGreen = Color(red: 0.204, green: 0.780, blue: 0.349)   // #34C759
    public static let warningOrange = Color(red: 1.0, green: 0.624, blue: 0.039)   // #FF9F0A
    public static let errorRed = Color(red: 1.0, green: 0.231, blue: 0.188)        // #FF3B30
    public static let outlineVariant = Color(red: 0.255, green: 0.278, blue: 0.333)// #414755

    // Terminal Colors
    public static let terminalBackground = Color(red: 0.094, green: 0.094, blue: 0.094) // #181818
    public static let terminalForeground = Color(red: 0.831, green: 0.831, blue: 0.831) // #D4D4D4

    public static func statusColor(for status: RunnerStatus) -> Color {
        switch status {
        case .idle:
            return onlineGreen
        case .busy:
            return warningOrange
        case .offline:
            return .secondary
        case .faulted:
            return errorRed
        case .restarting:
            return accentBlue
        }
    }
}
