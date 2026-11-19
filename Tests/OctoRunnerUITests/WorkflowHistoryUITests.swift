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
}
