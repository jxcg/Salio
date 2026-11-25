import XCTest

@MainActor
final class SalioUITests: XCTestCase {
    func testNearbySharesPlacesAndSelectionWithMapWithoutFetchingAgain() {
        let app = launch(arguments: ["-SALIOStubSearch", "-SALIOStubLocation", "-SALIOShowSearchCount"])
        let cafe = app.buttons["stub-cafe"]
        XCTAssertTrue(cafe.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["stub-cinema"].exists)
        XCTAssertFalse(app.staticTexts["Nearby"].exists)
        XCTAssertEqual(searchCount(in: app), 1)

        app.buttons["show-map"].tap()
        let cinemaPin = app.buttons["pin-stub-cinema"]
        XCTAssertTrue(cinemaPin.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["pin-stub-cafe"].exists)
        XCTAssertFalse(app.staticTexts["Nearby"].exists)
        cinemaPin.tap()
        app.buttons["show-list"].tap()
        XCTAssertTrue(app.buttons["stub-cinema"].isSelected)
        XCTAssertEqual(searchCount(in: app), 1)

        app.buttons["refresh-nearby"].tap()
        XCTAssertTrue(app.staticTexts["Searches: 2"].waitForExistence(timeout: 10))
    }

    func testLocationOffStillAllowsSearch() {
        let app = launch(arguments: ["-SALIOStubSearch", "-SALIOShowSearchCount"])
        XCTAssertTrue(app.staticTexts["Search places or turn on location to see what’s nearby."].waitForExistence(timeout: 10))
        XCTAssertEqual(searchCount(in: app), 0)
        searchField(in: app).tap()
        searchField(in: app).typeText("coffee\n")
        XCTAssertTrue(app.buttons["stub-cafe"].waitForExistence(timeout: 10))
        XCTAssertEqual(searchCount(in: app), 1)
    }

    func testSamplePlacesAppearWithoutServerConfiguration() {
        let app = launch(arguments: ["-SALIOStubSearch"])

        XCTAssertTrue(app.staticTexts["The Picture House"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["North Street Gallery"].exists)
    }

    #if compiler(>=6.4.4) && targetEnvironment(simulator)
    func testDuoKeepsNearbyAndSelectionAcrossHingeChanges() throws {
        guard #available(iOS 27.3, *) else { throw XCTSkip("Hinge automation requires iOS 27.3") }
        guard let hinge = XCUIDevice.shared.hinge else { throw XCTSkip("Requires the Duo simulator") }
        defer { hinge.angle = 0 }
        hinge.angle = 0

        let app = launch(arguments: ["-SALIOStubSearch"])
        let gallery = app.buttons.containing(.staticText, identifier: "North Street Gallery").firstMatch
        XCTAssertTrue(gallery.waitForExistence(timeout: 5))
        gallery.tap()
        XCTAssertTrue(gallery.isSelected)

        hinge.angle = .pi / 2
        hinge.angle = .pi
        XCTAssertTrue(app.navigationBars["Timing"].waitForExistence(timeout: 5))
        XCTAssertTrue(searchField(in: app).exists)
        XCTAssertTrue(gallery.isSelected)

        hinge.angle = 0
        XCTAssertTrue(searchField(in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(gallery.isSelected)
    }
    #endif

    func testInterestSetupIsOptionalAndSkipPersists() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-SALIOStubSearch"]
        app.launchEnvironment["SALIO_PROFILE_TEST_STORE"] = UUID().uuidString
        app.launch()

        let skip = app.buttons["Skip for now"]
        XCTAssertTrue(skip.waitForExistence(timeout: 5))
        XCTAssertTrue(searchField(in: app).isHittable)
        skip.tap()
        XCTAssertFalse(app.buttons["Choose interests"].exists)

        app.terminate()
        app.launch()
        XCTAssertTrue(searchField(in: app).waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Choose interests"].exists)
        app.buttons["Profile"].tap()
        XCTAssertTrue(app.switches["Film"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.switches["Film"].value as? String, "0")
    }

    func testInterestSetupChangesNearbyOrderOnRefresh() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-SALIOStubSearch", "-SALIOStubLocation"]
        app.launchEnvironment["SALIO_PROFILE_TEST_STORE"] = UUID().uuidString
        app.launch()

        let choose = app.buttons["Choose interests"]
        let cinema = app.buttons["stub-cinema"]
        let cafe = app.buttons["stub-cafe"]
        XCTAssertTrue(cinema.waitForExistence(timeout: 10))
        XCTAssertLessThan(cafe.frame.midY, cinema.frame.midY)
        choose.tap()
        let film = app.switches["Film"]
        XCTAssertTrue(film.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["profile-budget"].exists)
        XCTAssertFalse(app.switches["Walking"].exists)
        tapToggle(film)
        app.buttons["Save"].tap()
        XCTAssertTrue(searchField(in: app).waitForExistence(timeout: 5))
        XCTAssertFalse(choose.exists)

        app.buttons["refresh-nearby"].tap()
        XCTAssertTrue(cinema.waitForExistence(timeout: 10))
        XCTAssertLessThan(cinema.frame.midY, cafe.frame.midY)

        app.terminate()
        app.launch()
        XCTAssertTrue(cinema.waitForExistence(timeout: 10))
        XCTAssertFalse(choose.exists)
        XCTAssertLessThan(cinema.frame.midY, cafe.frame.midY)
    }

    func testProfileSavesAndResetsAcrossAppRelaunches() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-SALIOStubSearch", "-SALIOStubLocation"]
        app.launchEnvironment["SALIO_PROFILE_TEST_STORE"] = UUID().uuidString
        app.launch()

        let profile = app.buttons["Profile"]
        guard profile.waitForExistence(timeout: 5) else {
            XCTFail("Profile is not available from Nearby")
            return
        }
        profile.tap()
        let film = app.switches["Film"]
        let walking = app.switches["Walking"]
        let transit = app.switches["Public transport"]
        XCTAssertTrue(film.waitForExistence(timeout: 5))
        XCTAssertEqual(film.value as? String, "0")
        tapToggle(film)
        app.navigationBars["Profile"].swipeDown()
        XCTAssertEqual(film.value as? String, "1")
        app.buttons["Cancel"].tap()
        app.alerts.buttons["Keep editing"].tap()
        XCTAssertEqual(film.value as? String, "1")
        let budget = app.buttons["profile-budget"]
        budget.tap()
        app.buttons["££"].tap()
        app.swipeUp()
        tapToggle(walking)
        tapToggle(transit)
        app.buttons["Save"].tap()
        XCTAssertTrue(app.textFields["search-field"].waitForExistence(timeout: 5))

        app.terminate()
        app.launch()
        let cinema = app.buttons["stub-cinema"]
        let cafe = app.buttons["stub-cafe"]
        XCTAssertTrue(cinema.waitForExistence(timeout: 10))
        XCTAssertTrue(cafe.exists)
        XCTAssertLessThan(cinema.frame.midY, cafe.frame.midY)
        profile.tap()
        XCTAssertEqual(film.value as? String, "1")
        XCTAssertEqual(budget.value as? String, "££")
        app.swipeUp()
        XCTAssertEqual(walking.value as? String, "1")
        XCTAssertEqual(transit.value as? String, "1")
        app.buttons["Reset preferences"].tap()
        app.alerts.buttons["Cancel"].tap()
        XCTAssertEqual(walking.value as? String, "1")
        app.buttons["Reset preferences"].tap()
        app.alerts.buttons["Reset"].tap()

        app.terminate()
        app.launch()
        XCTAssertTrue(cafe.waitForExistence(timeout: 10))
        XCTAssertTrue(cinema.exists)
        XCTAssertLessThan(cafe.frame.midY, cinema.frame.midY)
        profile.tap()
        XCTAssertEqual(film.value as? String, "0")
        XCTAssertEqual(budget.value as? String, "Not set")
        app.swipeUp()
        XCTAssertEqual(walking.value as? String, "0")
        XCTAssertEqual(transit.value as? String, "0")
        XCTAssertFalse(app.buttons["Reset preferences"].exists)
    }

    private func tapToggle(_ toggle: XCUIElement) {
        // The accessibility element spans the row; the switch control is at its trailing edge.
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertEqual(toggle.value as? String, "1")
    }

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
