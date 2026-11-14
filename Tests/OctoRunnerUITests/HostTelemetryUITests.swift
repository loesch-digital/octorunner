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
        XCTAssertTrue(app.descendants(matching: .any)["CPU Load"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["Unified Memory"].firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any)["Storage & Device I/O"].firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any)["GitHub API"].firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any)["Memory pressure"].firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any)["Thermal state"].firstMatch.exists)
        let refresh = app.buttons["Refresh telemetry"].firstMatch
        XCTAssertTrue(refresh.isHittable)
        let cpu = app.staticTexts["telemetry.cpuUsage"].firstMatch
        let measured = expectation(for: NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "%", "%"), evaluatedWith: cpu)
        wait(for: [measured], timeout: 15)
        // MainShell has redrawn several times during the first sampling window.
        // A refresh must retain the baseline instead of replacing it with —.
        let lostBaseline = expectation(for: NSPredicate(format: "label == %@ OR value == %@", "—", "—"), evaluatedWith: cpu)
        lostBaseline.isInverted = true
        refresh.click()
        wait(for: [lostBaseline], timeout: 1)
        XCTAssertTrue(app.descendants(matching: .any)["Sample interval"].firstMatch.exists)
        let processes = app.descendants(matching: .any)["Processes by Runner"].firstMatch
        if !processes.isHittable { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(processes.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.popUpButtons["Process runner filter"].firstMatch.exists)
        app.outlines.staticTexts["All Runners"].firstMatch.click()
        XCTAssertTrue(app.buttons["New Runner"].firstMatch.waitForExistence(timeout: 5))
    }
}
