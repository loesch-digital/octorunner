import AppKit
import SwiftUI

@MainActor
public enum DashboardWindowCoordinator {
    /// Returns `true` only if no visible Dashboard window (`"OctoRunner"`) is currently open.
    public static func shouldOpenNewWindow(visibleWindowTitles: [String]) -> Bool {
        !visibleWindowTitles.contains(where: { $0.localizedStandardContains("OctoRunner") })
    }

    /// Brings an existing Dashboard window to the front if one is already open, or opens the single-instance window if closed.
    public static func activateOrOpenDashboard(openWindow: OpenWindowAction) {
        NSApplication.shared.setActivationPolicy(.regular)
        let candidateWindows = NSApplication.shared.windows.filter { window in
            window.canBecomeMain && (window.title.localizedStandardContains("OctoRunner") || window.identifier?.rawValue.contains("main-dashboard") == true)
        }
        let visibleTitles = candidateWindows.filter(\.isVisible).map { $0.title.isEmpty ? "OctoRunner" : $0.title }

        if let existing = candidateWindows.first(where: \.isVisible) {
            existing.deminiaturize(nil)
            existing.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }

        if let hidden = candidateWindows.first {
            hidden.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }

        if shouldOpenNewWindow(visibleWindowTitles: visibleTitles) {
            openWindow(id: "main-dashboard")
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }

    /// Closes the Dashboard window while keeping OctoRunner active in the macOS Menu Bar.
    public static func hideDashboardWindowToMenuBar() {
        for window in NSApplication.shared.windows where window.canBecomeMain {
            window.orderOut(nil)
        }
    }
}
