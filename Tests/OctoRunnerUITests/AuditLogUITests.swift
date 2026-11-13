import XCTest

@MainActor
final class AuditLogUITests: XCTestCase {
    func testAuditDialogFiltersStoredHistoryAndReturnsToDashboard() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-preferences.language", "en"]
        app.launch()
        let closeAuthentication = app.buttons["Close"].firstMatch
        if closeAuthentication.waitForExistence(timeout: 5) { closeAuthentication.click() }
        let audit = app.buttons["Audit Log"].firstMatch
        XCTAssertTrue(audit.waitForExistence(timeout: 10), app.debugDescription)
        audit.click()
        let search = app.textFields["Search event titles and details"].firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5), app.debugDescription)
        search.click()
        search.typeText("no-matching-event-" + UUID().uuidString)
        XCTAssertTrue(app.staticTexts["No matching audit events"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["Reset filters"].firstMatch.click()
        XCTAssertTrue(app.buttons["App started"].firstMatch.waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["App started"].firstMatch.click()
        XCTAssertTrue(app.staticTexts["Event ID"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["Close"].firstMatch.click()
        XCTAssertTrue(app.textFields["Search event titles and details"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["Close"].firstMatch.click()
        XCTAssertTrue(app.buttons["New Runner"].firstMatch.waitForExistence(timeout: 5))
    }
}
