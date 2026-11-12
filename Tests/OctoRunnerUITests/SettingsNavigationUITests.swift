import XCTest

@MainActor
final class SettingsNavigationUITests: XCTestCase {
    func testEverySettingsCategoryIsVisibleAndSelectable() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-preferences.language", "en"]
        app.launch()
        let closeAuthentication = app.buttons["Close"].firstMatch
        if closeAuthentication.waitForExistence(timeout: 5) { closeAuthentication.click() }
        let settings = app.outlines.staticTexts["App Settings"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 10), app.debugDescription)
        settings.click()
        let categories = ["General", "Autostart & Background", "Failover", "Auth & Tokens", "Notifications"]
        // Test all categories before selecting any: overflow navigation must not
        // make a hidden category count as visible merely because we selected it.
        for category in categories {
            let button = app.buttons[category].firstMatch
            XCTAssertTrue(button.waitForExistence(timeout: 5), category)
            XCTAssertTrue(button.isHittable, "Category is hidden or obstructed: \(category)")
        }
        let content = ["Show icon in menu bar", "Launch at macOS login", "Restart policy", "Connect GitHub account…", "Enable macOS notifications"]
        for (category, control) in zip(categories, content) {
            app.buttons[category].firstMatch.click()
            XCTAssertTrue(app.descendants(matching: .any)[control].firstMatch.waitForExistence(timeout: 5), "Missing content for \(category)")
        }
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
