import XCTest

@MainActor
final class SearchPerformanceTests: XCTestCase {
    func testFixedSearch() throws {
        guard let fixtureURL = ProcessInfo.processInfo.environment["SALIO_PERF_FIXTURE_URL"] else {
            throw XCTSkip("Run the performance check with a sample feed fixture.")
        }
        let app = XCUIApplication()
        app.launchArguments = ["-SALIOStubSearch"]
        app.launchEnvironment["SALIO_API_URL"] = fixtureURL

        continueAfterFailure = false
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        options.invocationOptions = [.manuallyStart, .manuallyStop]
        measure(metrics: [XCTCPUMetric(application: app), XCTMemoryMetric(application: app)], options: options) {
            app.launch()
            defer { app.terminate() }

            XCTAssertTrue(app.staticTexts["The Picture House"].waitForExistence(timeout: 10))
            let search = app.textFields["search-field"]
            search.tap()
            search.typeText("coffee")

            startMeasuring()
            search.typeText("\n")
            let found = app.buttons["stub-cafe"].waitForExistence(timeout: 10)
            stopMeasuring()

            XCTAssertTrue(found)
        }
    }
}
