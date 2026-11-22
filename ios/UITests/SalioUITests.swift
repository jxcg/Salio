import XCTest

final class SalioUITests: XCTestCase {
    func testSubmittingNonEmptyQueryRunsOneSearchAndSelectionSurvivesLifecycle() {
        let app = launch(arguments: ["-SALIOStubSearch", "-SALIOShowSearchCount"])
        XCTAssertTrue(searchField(in: app).waitForExistence(timeout: 15))

        searchField(in: app).tap()
        searchField(in: app).typeText("coffee\n")

        let started = Date()
        let firstResult = app.buttons["stub-cafe"]
        XCTAssertTrue(firstResult.waitForExistence(timeout: 15))
        print("SALIO_LATENCY submit-to-result: \(Date().timeIntervalSince(started)) s")
        XCTAssertEqual(searchCount(in: app), 1)

        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(firstResult.waitForExistence(timeout: 10))
        XCTAssertEqual(searchCount(in: app), 1)

        firstResult.tap()
        XCTAssertTrue(firstResult.isSelected)
        XCTAssertEqual(searchCount(in: app), 1)
    }

    func testSubmittingEmptyQueryDoesNotSearch() {
        let app = launch(arguments: ["-SALIOStubSearch", "-SALIOShowSearchCount"])
        XCTAssertTrue(searchField(in: app).waitForExistence(timeout: 15))

        searchField(in: app).tap()
        searchField(in: app).typeText("\n")
        XCTAssertEqual(searchCount(in: app), 0)
    }

    func testEmptyResultShowsEmptyStateAfterOneSearch() {
        let app = launch(arguments: ["-SALIOStubSearchEmpty", "-SALIOShowSearchCount"])
        XCTAssertTrue(searchField(in: app).waitForExistence(timeout: 15))

        searchField(in: app).tap()
        searchField(in: app).typeText("coffee\n")

        XCTAssertTrue(app.staticTexts["No matches. Try a different search."].waitForExistence(timeout: 15))
        XCTAssertEqual(searchCount(in: app), 1)
    }

    func testSearchErrorShowsErrorStateAfterOneSearch() {
        let app = launch(arguments: ["-SALIOStubSearchError", "-SALIOShowSearchCount"])
        XCTAssertTrue(searchField(in: app).waitForExistence(timeout: 15))

        searchField(in: app).tap()
        searchField(in: app).typeText("coffee\n")

        XCTAssertTrue(app.staticTexts["Can’t search right now. Try again."].waitForExistence(timeout: 15))
        XCTAssertEqual(searchCount(in: app), 1)
    }

    private func launch(arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += arguments
        app.launchEnvironment["SALIO_API_URL"] = "http://127.0.0.1:8765"
        app.launch()
        return app
    }

    private func searchField(in app: XCUIApplication) -> XCUIElement {
        app.textFields["search-field"]
    }

    private func searchCount(in app: XCUIApplication) -> Int {
        let label = app.descendants(matching: .any)["search-count"].label
        return Int(label.components(separatedBy: ": ").last ?? "") ?? -1
    }
}
