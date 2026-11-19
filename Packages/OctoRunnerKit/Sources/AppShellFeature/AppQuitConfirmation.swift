import AppKit

@MainActor
public enum AppQuitConfirmation {
    public static func makeAlert(locale: Locale = .current) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = AppLocalization.string("Confirm quitting OctoRunner", locale: locale)
        alert.informativeText = AppLocalization.string("""
        OctoRunner and its menu bar item will close. Installed runner LaunchAgents continue running through launchd.

        Imported runners that have not been migrated remain under their previous process manager. OctoRunner cannot guarantee that they continue running or are supervised after quitting.
        """, locale: locale)
        alert.addButton(withTitle: AppLocalization.string("Quit OctoRunner", locale: locale))
        alert.addButton(withTitle: AppLocalization.string("Cancel", locale: locale)).keyEquivalent = "\u{1b}"
        return alert
    }

    public static func shouldTerminate(after response: NSApplication.ModalResponse) -> Bool {
        response == .alertFirstButtonReturn
    }
}
