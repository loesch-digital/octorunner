import XCTest

@MainActor
final class WorkflowTransitionUITests: XCTestCase {
    func testWorkflowDetailsAccessibility() throws {
        try checkWorkflowDetails(language: "en", close: "Close workflow details", open: "View workflow details",
                                 loadLog: "Load job log", github: "Open job on GitHub")
    }

    func testWorkflowDetailsAccessibilityInGerman() throws {
        try checkWorkflowDetails(language: "de", close: "Workflow-Details schließen", open: "Workflow-Details anzeigen",
                                 loadLog: "Job-Log laden", github: "Job auf GitHub öffnen")
    }

    func testWorkflowCountersAndRunnerCardFollowPolling() throws {
        try withFixture { app, directory in
            let sidebar = app.outlines.firstMatch
            let history = sidebar.staticTexts["Jobs & Workflow Runs"]
            let activeBadge = sidebar.staticTexts["Running workflows: 1"]
            let currentJob = app.buttons["Main CI · Fixture Build"]
            XCTAssertTrue(currentJob.waitForExistence(timeout: 15))
            XCTAssertTrue(activeBadge.exists)
            history.click()
            XCTAssertTrue(app.staticTexts["1 / 1"].waitForExistence(timeout: 10))

            try writeObservation(1, to: directory)
            XCTAssertTrue(app.staticTexts["1 / 0"].waitForExistence(timeout: 10))
            XCTAssertTrue(activeBadge.exists)
            sidebar.staticTexts["All runners"].click()
            XCTAssertTrue(app.buttons["PR CI · Fixture PR Build"].waitForExistence(timeout: 10))
            XCTAssertFalse(currentJob.exists)
            XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Failed")).firstMatch.exists)
            XCTAssertTrue(sidebar.staticTexts["1"].exists)
            XCTAssertTrue(sidebar.staticTexts["0"].exists)

            history.click()
            try writeObservation(2, to: directory)
            XCTAssertTrue(app.staticTexts["0 / 0"].waitForExistence(timeout: 10))
            XCTAssertTrue(activeBadge.waitForNonExistence(timeout: 10))
            XCTAssertTrue(app.staticTexts["2"].exists)
        }
    }

    func testLiveLogAccessibility() throws {
        try withFixture { app, _ in
            let liveLog = app.buttons["Live Log"]
            XCTAssertTrue(liveLog.waitForExistence(timeout: 10))
            liveLog.click()
            let done = app.buttons["Done"]
            XCTAssertTrue(done.waitForExistence(timeout: 10))
            let logLine = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label CONTAINS[c] %@ OR value CONTAINS[c] %@",
                                      "Fixture runner log line", "Fixture runner log line")).firstMatch
            XCTAssertTrue(logLine.waitForExistence(timeout: 10))
            done.click()
            XCTAssertTrue(done.waitForNonExistence(timeout: 5))
        }
    }

    private func checkWorkflowDetails(language: String, close: String, open: String, loadLog: String, github: String) throws {
        try withFixture(language: language) { app, _ in
            let currentJob = app.buttons["Main CI · Fixture Build"]
            let dismiss = app.buttons[close]
            XCTAssertTrue(currentJob.waitForExistence(timeout: 15))

            currentJob.click()
            try checkJob(app, loadLog: loadLog, github: github)
            dismiss.click()
            XCTAssertTrue(dismiss.waitForNonExistence(timeout: 5))

            app.buttons[open].firstMatch.click()
            try checkJob(app, loadLog: loadLog, github: github)
            dismiss.click()
            XCTAssertTrue(dismiss.waitForNonExistence(timeout: 5))
        }
    }

    private func checkJob(_ app: XCUIApplication, loadLog: String, github: String) throws {
        let action = app.buttons[loadLog]
        XCTAssertTrue(action.waitForExistence(timeout: 10))
        XCTAssertTrue(app.links[github].exists)
        let disclosure = app.disclosureTriangles.firstMatch
        XCTAssertTrue(disclosure.exists)
        XCTAssertTrue(app.debugDescription.contains("Fixture Checkout"))
        disclosure.click()
        XCTAssertTrue(action.waitForNonExistence(timeout: 5))
        disclosure.click()
        XCTAssertTrue(action.waitForExistence(timeout: 5))
    }

    private func withFixture(language: String = "en", _ test: (XCUIApplication, URL) throws -> Void) throws {
        continueAfterFailure = false
        let directory = FileManager.default.temporaryDirectory.appending(path: "OctoRunner-workflow-\(UUID())")
        let diagnostics = directory.appending(path: "_diag")
        try FileManager.default.createDirectory(at: diagnostics, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try "[2026-11-26 13:11:20Z INFO Terminal] Fixture runner log line\n".write(
            to: diagnostics.appending(path: "Runner_fixture.log"), atomically: true, encoding: .utf8)
        try writeObservation(0, to: directory)
        let app = XCUIApplication()
        app.launchEnvironment["OCTORUNNER_WORKFLOW_UI_TEST_DIRECTORY"] = directory.path
        app.launchEnvironment["OCTORUNNER_WORKFLOW_UI_TEST_LANGUAGE"] = language
        app.launchArguments = ["-AppleLanguages", "(\(language))", "-AppleLocale", language == "de" ? "de_DE" : "en_US"]
        app.launch()
        defer { app.terminate() }
        try test(app, directory)
    }

    private func writeObservation(_ phase: Int, to directory: URL) throws {
        let completed = ISO8601DateFormatter().string(from: .now.addingTimeInterval(-2))
        func observation(_ runID: Int, workflow: String, job: String, status: String, conclusion: String?) -> [String: Any] {
            var run: [String: Any] = ["id": runID, "run_attempt": 1, "name": workflow, "status": status,
                                      "head_branch": "main", "head_sha": "abc123", "run_started_at": completed]
            var job: [String: Any] = ["id": runID + 100, "run_id": runID, "name": job, "status": status,
                                      "runner_id": 31, "runner_name": "Fixture Runner", "started_at": completed,
                                      "steps": [["number": 1, "name": "Fixture Checkout", "status": "completed", "conclusion": "success"]]]
            if let conclusion {
                run["conclusion"] = conclusion
                job["conclusion"] = conclusion
                job["completed_at"] = completed
            }
            return ["run": run, "jobs": [job]]
        }
        let observations = [
            observation(10, workflow: "Main CI", job: "Fixture Build",
                        status: phase == 0 ? "in_progress" : "completed", conclusion: phase == 0 ? nil : "failure"),
            observation(20, workflow: "PR CI", job: "Fixture PR Build",
                        status: phase == 0 ? "queued" : (phase == 1 ? "in_progress" : "completed"), conclusion: phase < 2 ? nil : "success")
        ]
        try JSONSerialization.data(withJSONObject: observations).write(to: directory.appending(path: "history.json"), options: .atomic)
    }
}
