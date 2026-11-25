import XCTest

@MainActor
final class WorkflowHistoryUITests: XCTestCase {
    func testJobsNavigationAndSearchRemainInMainWindow() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-preferences.language", "en"]
        app.launch()
        let close = app.buttons["Close"].firstMatch
        if close.waitForExistence(timeout: 5) { close.click() }
        let jobs = app.outlines.staticTexts["Jobs & Workflow Runs"].firstMatch
        XCTAssertTrue(jobs.waitForExistence(timeout: 10), app.debugDescription)
        jobs.click()
        let search = app.textFields["Search workflow history"].firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5), app.debugDescription)
        search.click()
        search.typeText("PR #12")
        XCTAssertEqual(app.windows.count, 1, app.debugDescription)
        app.outlines.staticTexts["All Runners"].firstMatch.click()
        XCTAssertTrue(app.buttons["New Runner"].firstMatch.waitForExistence(timeout: 5))
    }

    func testHistorySourcesCanCloseWithoutLosingSidebarNavigation() throws {
        continueAfterFailure = false
        let home = FileManager.default.temporaryDirectory.appending(path: "OctoRunnerUITest-\(UUID())")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let app = XCUIApplication()
        app.launchEnvironment["CFFIXED_USER_HOME"] = home.path
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-preferences.language", "en"]
        defer {
            app.terminate()
            try? FileManager.default.removeItem(at: home)
        }
        app.launch()
        let closeAuthentication = app.buttons["Close"].firstMatch
        if closeAuthentication.waitForExistence(timeout: 5) { closeAuthentication.click() }
        let jobs = app.outlines.staticTexts["Jobs & Workflow Runs"].firstMatch
        XCTAssertTrue(jobs.waitForExistence(timeout: 10), app.debugDescription)
        jobs.click()

        let sources = app.buttons["History sources"].firstMatch
        XCTAssertTrue(sources.waitForExistence(timeout: 5), app.debugDescription)
        sources.click()
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(sheet.textFields["Additional history repository"].firstMatch.exists, app.debugDescription)
        sheet.buttons["Close"].firstMatch.click()
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 5), app.debugDescription)

        let runners = app.outlines.staticTexts["All Runners"].firstMatch
        XCTAssertTrue(runners.isHittable, app.debugDescription)
        runners.click()
        XCTAssertTrue(app.buttons["New Runner"].firstMatch.waitForExistence(timeout: 5))
    }
}
