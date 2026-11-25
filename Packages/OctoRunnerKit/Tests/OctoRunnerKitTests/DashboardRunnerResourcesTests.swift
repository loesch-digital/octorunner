import AppKit
@testable import AppShellFeature
import SwiftUI
@testable import TelemetryKit
import Testing

@MainActor
struct DashboardRunnerResourcesTests {
    @Test("Runner resources fit the status row in both languages and appearances")
    func responsiveStatusLine() {
        let usage = RunnerResourceUsage(cpuPercent: 164, residentBytes: 3_800_000_000)
        for language in ["de", "en"] {
            let locale = Locale(identifier: language)
            #expect(AppLocalization.string("Measure Work Folder", locale: locale) ==
                (language == "de" ? "Ordnergröße ermitteln" : "Measure Work Folder"))
            for scheme in [ColorScheme.light, .dark] {
                let narrow = hostedSize(width: 240, usage: usage, locale: locale, scheme: scheme)
                let wide = hostedSize(width: 760, usage: usage, locale: locale, scheme: scheme)
                #expect(narrow.width <= 240)
                #expect(wide.width <= 760)
                #expect(narrow.height > wide.height)
                #expect(narrow.height <= 100)
            }
        }
    }

    private func hostedSize(width: CGFloat, usage: RunnerResourceUsage, locale: Locale, scheme: ColorScheme) -> CGSize {
        let view = DashboardRunnerResourceLine(
            runnerName: "mac-studio-1", usage: usage, workFolderPath: "/tmp/example/_work"
        ) { Text("Running · Managed · PID 53194").fixedSize() }
            .environment(\.locale, locale)
            .environment(\.colorScheme, scheme)
            .frame(width: width)
        let host = NSHostingView(rootView: view)
        host.frame = CGRect(x: 0, y: 0, width: width, height: 100)
        host.layoutSubtreeIfNeeded()
        #expect(host.bitmapImageRepForCachingDisplay(in: host.bounds) != nil)
        return host.fittingSize
    }
}
