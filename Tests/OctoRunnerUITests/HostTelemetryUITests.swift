import XCTest

@MainActor
final class HostTelemetryUITests: XCTestCase {
    func testTelemetryNavigationAndSamplingControls() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-preferences.language", "en"]
        app.launch()
        let close = app.buttons["Close"].firstMatch
        if close.waitForExistence(timeout: 5) { close.click() }
        let telemetry = app.outlines.staticTexts["Host Telemetry"].firstMatch
        XCTAssertTrue(telemetry.waitForExistence(timeout: 10), app.debugDescription)
        telemetry.click()
        XCTAssertTrue(app.staticTexts["CPU Load"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Unified Memory"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["Storage & Device I/O"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["GitHub API"].firstMatch.exists)
        let refresh = app.buttons["Refresh telemetry"].firstMatch
        XCTAssertTrue(refresh.isHittable)
        let cpu = app.staticTexts["telemetry.cpuUsage"].firstMatch
        let measured = expectation(for: NSPredicate(format: "label CONTAINS %@", "%"), evaluatedWith: cpu)
        wait(for: [measured], timeout: 15)
        // MainShell has redrawn several times during the first sampling window.
        // A refresh must retain the baseline instead of replacing it with —.
        let lostBaseline = expectation(for: NSPredicate(format: "label == %@", "—"), evaluatedWith: cpu)
        lostBaseline.isInverted = true
        refresh.click()
        wait(for: [lostBaseline], timeout: 1)
        XCTAssertTrue(app.descendants(matching: .any)["Sample interval"].firstMatch.exists)
        app.outlines.staticTexts["All Runners"].firstMatch.click()
        XCTAssertTrue(app.buttons["New Runner"].firstMatch.waitForExistence(timeout: 5))
    }
}
