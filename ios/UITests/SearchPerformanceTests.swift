import XCTest

@MainActor
final class SearchPerformanceTests: XCTestCase {
    func testFixedSearch() throws {
        guard ProcessInfo.processInfo.environment["SALIO_PERF_ENABLED"] == "1" else {
            throw XCTSkip("Run the performance check with SALIO_PERF_ENABLED=1.")
        }
        let app = XCUIApplication()
        app.launchArguments = ["-SALIOStubSearch", "-finishedOnboarding", "YES"]

        continueAfterFailure = false
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        options.invocationOptions = [.manuallyStart, .manuallyStop]
        measure(metrics: [XCTCPUMetric(application: app), XCTMemoryMetric(application: app)], options: options) {
            app.launch()
            defer { app.terminate() }

            let search = app.textFields["search-field"]
            XCTAssertTrue(search.waitForExistence(timeout: 10))
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
