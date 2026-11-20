import AppKit
import GitHubAPI

@MainActor
public enum AppUpdatePresentation {
    public static func makeAlert(_ notice: AppUpdateNotice, locale: Locale) -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = AppLocalization.string(title(notice), locale: locale)
        alert.informativeText = AppLocalization.string(message(notice), locale: locale)
        alert.addButton(withTitle: AppLocalization.string("OK", locale: locale))
        return alert
    }

    static func title(_ notice: AppUpdateNotice) -> String.LocalizationValue {
        switch notice {
        case .inProgress: "OctoRunner is installing an update"
        case .restoredPreviousVersion: "Previous OctoRunner version restored"
        case .installationFailed: "OctoRunner could not install the update"
        case .recoveryRequired: "OctoRunner update needs recovery"
        }
    }

    static func message(_ notice: AppUpdateNotice) -> String.LocalizationValue {
        switch notice {
        case .inProgress:
            "Wait for the installation to finish. OctoRunner will reopen automatically."
        case .restoredPreviousVersion:
            "The updated app could not start. OctoRunner restored your previous version and local runner data."
        case .installationFailed:
            "You can download the signed macOS archive from GitHub Releases."
        case .recoveryRequired:
            "OctoRunner could not complete update recovery. Keep the backup files and check the recovery section of the documentation."
        }
    }
}
