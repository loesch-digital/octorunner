import AppKit
import DesignSystem
import SwiftUI
import Testing

@MainActor
struct RunnerStatusColorTests {
    @Test("Busy badges use the menu bar blue in Light and Dark")
    func busyUsesBlue() throws {
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            let appearance = try #require(NSAppearance(named: name))
            appearance.performAsCurrentDrawingAppearance {
                let actual = NSColor(OctoTheme.statusColor(for: .busy)).usingColorSpace(.sRGB)!
                let expected = NSColor(OctoTheme.accentBlue).usingColorSpace(.sRGB)!
                #expect(abs(actual.redComponent - expected.redComponent) < 0.001)
                #expect(abs(actual.greenComponent - expected.greenComponent) < 0.001)
                #expect(abs(actual.blueComponent - expected.blueComponent) < 0.001)
            }

            let view = NSHostingView(rootView: RunnerStatusBadge(status: .busy)
                .environment(\.colorScheme, name == .darkAqua ? .dark : .light))
            view.appearance = appearance
            view.frame = NSRect(x: 0, y: 0, width: 100, height: 32)
            view.layoutSubtreeIfNeeded()
            let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let hasBlue = (0..<bitmap.pixelsWide).contains { x in
                (0..<bitmap.pixelsHigh).contains { y in
                    guard let pixel = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { return false }
                    return pixel.alphaComponent > 0.5 && pixel.blueComponent > pixel.redComponent + 0.2
                }
            }
            #expect(hasBlue, "Busy badge must visibly render blue in \(name.rawValue)")
        }
    }
}
