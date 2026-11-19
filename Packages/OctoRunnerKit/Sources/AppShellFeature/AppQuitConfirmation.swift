import AppKit
import RunnerEngine

@MainActor
public enum AppQuitConfirmation {
    public static func makeAlert(locale: Locale = .current) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = AppLocalization.string("Confirm quitting OctoRunner", locale: locale)
        alert.informativeText = AppLocalization.string("""
        OctoRunner and its menu bar item will close. Directly managed runners must be idle before OctoRunner can stop them and quit. Installed runner LaunchAgents continue running through launchd.

        Imported runners stay under their existing process manager.
        """, locale: locale)
        alert.addButton(withTitle: AppLocalization.string("Quit OctoRunner", locale: locale))
        alert.addButton(withTitle: AppLocalization.string("Cancel", locale: locale)).keyEquivalent = "\u{1b}"
        return alert
    }

    public static func shouldTerminate(after response: NSApplication.ModalResponse) -> Bool {
        response == .alertFirstButtonReturn
    }

    public static func makeBlockedAlert(error: any Error, locale: Locale) -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = AppLocalization.string("OctoRunner is still open", locale: locale)
        alert.informativeText = switch error as? RunnerSupervisionError {
        case .runnerBusy:
            AppLocalization.string("A directly managed runner is processing a job. Try quitting after the job finishes.", locale: locale)
        case .activityUnknown, .operationInProgress:
            AppLocalization.string("OctoRunner is waiting for a runner status. Try quitting again shortly.", locale: locale)
        default:
            AppLocalization.string("A runner could not be stopped. Check its status before quitting again.", locale: locale)
        }
        alert.addButton(withTitle: "OK")
        return alert
    }
}
