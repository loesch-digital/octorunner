import AppKit
@testable import AppShellFeature
import SwiftUI
import Testing

@MainActor
struct DashboardScreenshotTests {
    @Test("The public screenshot uses example runner resource readings")
    func exportDashboard() throws {
        let usage = try #require(DashboardPreview.resourceUsage["mac-studio-1"])
        #expect(usage.cpuPercent == 164)
        #expect((usage.residentBytes ?? 0) > 0)
        #expect(DashboardPreview.resourceUsage["mac-mini-1"] == nil)

        guard let output = ProcessInfo.processInfo.environment["OCTORUNNER_DASHBOARD_SCREENSHOT"] else { return }
        let container = try DashboardPreview.makeContainer()
        let view = DashboardPreview(container: container, language: .english)
            .environment(\.colorScheme, .light)
            .frame(width: 1120, height: 772)
        let bounds = CGRect(x: 0, y: 0, width: 1120, height: 772)
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: bounds, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = host
        host.frame = bounds
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: bounds))
        host.cacheDisplay(in: bounds, to: bitmap)
        let data = try #require(bitmap.representation(using: .png, properties: [:]))
        try data.write(to: URL(filePath: output), options: .atomic)
    }
}
