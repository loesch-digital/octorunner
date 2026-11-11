import AppKit

@MainActor
public enum AppQuitConfirmation {
    public static func makeAlert() -> NSAlert {
        let alert = NSAlert()
        alert.messageText = "Quit OctoRunner?"
        alert.informativeText = """
        OctoRunner and its menu bar item will close. Installed runner LaunchAgents continue running through launchd.

        Imported runners that have not been migrated remain under their previous process manager. OctoRunner cannot guarantee that they continue running or are supervised after quitting.
        """
        alert.addButton(withTitle: "Quit OctoRunner")
        alert.addButton(withTitle: "Cancel").keyEquivalent = "\u{1b}"
        return alert
    }

    public static func shouldTerminate(after response: NSApplication.ModalResponse) -> Bool {
        response == .alertFirstButtonReturn
    }
}
