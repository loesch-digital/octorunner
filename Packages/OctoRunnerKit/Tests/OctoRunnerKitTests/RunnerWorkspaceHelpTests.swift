import AppKit
@testable import AppShellFeature
import SwiftUI
import Testing

@MainActor
struct RunnerWorkspaceHelpTests {
    @Test("Workspace guidance expands without overflowing the narrow wizard in either language")
    func expandedGuidanceFits() throws {
        for language in ["de", "en"] {
            for scheme in [ColorScheme.light, .dark] {
                let collapsed = NSHostingView(rootView: RunnerWorkspaceHelp(isExpanded: false)
                    .environment(\.locale, Locale(identifier: language)).preferredColorScheme(scheme)
                    .frame(width: 480))
                let expanded = NSHostingView(rootView: RunnerWorkspaceHelp(isExpanded: true)
                    .environment(\.locale, Locale(identifier: language)).preferredColorScheme(scheme)
                    .frame(width: 480))
                let size = expanded.fittingSize
                #expect(size.width <= 480)
                #expect(size.height > collapsed.fittingSize.height + 100)
                expanded.frame = CGRect(origin: .zero, size: size)
                expanded.layoutSubtreeIfNeeded()
                let bitmap = try #require(expanded.bitmapImageRepForCachingDisplay(in: expanded.bounds))
                expanded.cacheDisplay(in: expanded.bounds, to: bitmap)
                #expect(bitmap.pixelsWide > 0 && bitmap.pixelsHigh > 0)
                if let path = ProcessInfo.processInfo.environment["OCTORUNNER_LAYOUT_CAPTURE_DIR"] {
                    try #require(bitmap.representation(using: .png, properties: [:])).write(to:
                        URL(fileURLWithPath: path).appending(path: "workspace-help-\(language)-\(scheme == .dark ? "dark" : "light").png"))
                }
            }
        }
    }
}
