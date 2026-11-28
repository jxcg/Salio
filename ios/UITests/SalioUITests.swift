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
        XCTAssertTrue(app.buttons["turn-on-location"].exists)
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

    func testSkippingOnboardingShowsEverythingWithoutAskingForLocationAndStaysSkipped() {
        continueAfterFailure = false
        let app = storedApp(arguments: ["-SALIOStubSearch", "-SALIOStubLocation"], onboarded: false)
        app.launch()

        let skip = app.buttons["onboarding-skip"]
        XCTAssertTrue(app.buttons["onboarding-start"].waitForExistence(timeout: 5))
        skip.tap()
        XCTAssertTrue(searchField(in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["use-location"].exists)
        XCTAssertFalse(app.buttons["stub-cafe"].exists)
        app.buttons["use-location"].tap()
        XCTAssertTrue(app.buttons["stub-cafe"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["stub-restaurant"].exists)

        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["stub-cafe"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["onboarding-start"].exists)

        app.buttons["Profile"].tap()
        app.swipeUp()
        app.buttons["profile-set-up-again"].tap()
        XCTAssertTrue(app.buttons["onboarding-start"].waitForExistence(timeout: 5))
    }

    func testOnboardingChoiceFiltersNearbyAndShowsInProfile() {
        continueAfterFailure = false
        let app = storedApp(arguments: ["-SALIOStubSearch", "-SALIOStubLocation"], onboarded: false)
        app.launch()

        let start = app.buttons["onboarding-start"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()
        app.buttons["onboarding-kind-Restaurants"].tap()
        XCTAssertTrue(app.buttons["onboarding-kind-Restaurants"].isSelected)
        app.buttons["onboarding-continue"].tap()
        app.buttons["onboarding-allow-location"].tap()

        let restaurant = app.buttons["stub-restaurant"]
        XCTAssertTrue(restaurant.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["stub-cafe"].exists)
        XCTAssertFalse(app.buttons["stub-cinema"].exists)
        XCTAssertTrue(app.buttons["kind-Restaurants"].isSelected)

        app.buttons["Profile"].tap()
        XCTAssertTrue(app.switches["Restaurants"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.switches["Restaurants"].value as? String, "1")
        XCTAssertEqual(app.switches["Film"].value as? String, "0")
        app.buttons["Cancel"].tap()

        app.terminate()
        app.launch()
        XCTAssertTrue(restaurant.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["stub-cafe"].exists)
        XCTAssertFalse(start.exists)
    }

    func testFeedFilterLastsForTheSessionOnly() {
        continueAfterFailure = false
        let app = storedApp(arguments: ["-SALIOStubSearch", "-SALIOStubLocation", "-SALIOShowSearchCount"])
        app.launch()

        let cafe = app.buttons["stub-cafe"]
        let cinema = app.buttons["stub-cinema"]
        XCTAssertTrue(cafe.waitForExistence(timeout: 10))
        XCTAssertTrue(cinema.exists)
        XCTAssertTrue(app.buttons["kind-everything"].isSelected)
        XCTAssertFalse(app.buttons["kind-reset"].exists)

        app.buttons["kind-Film"].tap()
        XCTAssertTrue(cafe.waitForNonExistence(timeout: 5))
        XCTAssertTrue(cinema.exists)
        XCTAssertEqual(searchCount(in: app), 2)
        XCTAssertTrue(app.buttons["kind-reset"].exists)

        app.buttons["kind-Film"].tap()
        app.buttons["kind-Bars and nightlife"].tap()
        XCTAssertTrue(app.buttons["show-everything"].waitForExistence(timeout: 5))
        app.buttons["show-everything"].tap()
        XCTAssertTrue(cafe.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["kind-reset"].exists)

        app.buttons["kind-Film"].tap()
        XCTAssertTrue(cafe.waitForNonExistence(timeout: 5))
        app.buttons["Profile"].tap()
        XCTAssertTrue(app.switches["Film"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.switches["Film"].value as? String, "0")
        app.buttons["Cancel"].tap()

        app.terminate()
        app.launch()
        XCTAssertTrue(cafe.waitForExistence(timeout: 10))
        XCTAssertTrue(cinema.exists)
        XCTAssertFalse(app.buttons["kind-reset"].exists)
    }

    func testProfileSavesAndResetsAcrossAppRelaunches() {
        continueAfterFailure = false
        let app = storedApp(arguments: ["-SALIOStubSearch", "-SALIOStubLocation", "-SALIOShowSearchCount"])
        app.launch()

        let profile = app.buttons["Profile"]
        let cinema = app.buttons["stub-cinema"]
        let cafe = app.buttons["stub-cafe"]
        XCTAssertTrue(cafe.waitForExistence(timeout: 10))
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
        XCTAssertTrue(searchField(in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(cafe.waitForNonExistence(timeout: 5))
        XCTAssertTrue(cinema.exists)
        XCTAssertEqual(searchCount(in: app), 2)

        app.terminate()
        app.launch()
        XCTAssertTrue(cinema.waitForExistence(timeout: 10))
        XCTAssertFalse(cafe.exists)
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
        app.buttons["Cancel"].tap()

        app.terminate()
        app.launch()
        XCTAssertTrue(cafe.waitForExistence(timeout: 10))
        XCTAssertTrue(cinema.exists)
        XCTAssertFalse(app.buttons["onboarding-start"].exists)
        profile.tap()
        XCTAssertEqual(film.value as? String, "0")
        XCTAssertEqual(budget.value as? String, "Not set")
        app.swipeUp()
        XCTAssertEqual(walking.value as? String, "0")
        XCTAssertEqual(transit.value as? String, "0")
        XCTAssertFalse(app.buttons["Reset preferences"].exists)
    }

    func testThemeChoicePersistsAcrossRelaunches() {
        continueAfterFailure = false
        let app = storedApp(arguments: ["-SALIOStubSearch", "-SALIOStubLocation"])
        app.launch()

        let profile = app.buttons["Profile"]
        XCTAssertTrue(profile.waitForExistence(timeout: 10))
        profile.tap()
        app.swipeUp()

        let theme = app.buttons["profile-theme"]
        XCTAssertTrue(theme.waitForExistence(timeout: 5))
        XCTAssertEqual(theme.value as? String, "Mist & Glass")
        theme.tap()
        app.buttons["Stone & Amber"].tap()
        XCTAssertEqual(theme.value as? String, "Stone & Amber")
        XCTAssertFalse(app.buttons["Save"].isEnabled)
        app.buttons["Cancel"].tap()

        app.terminate()
        app.launch()
        XCTAssertTrue(profile.waitForExistence(timeout: 10))
        profile.tap()
        app.swipeUp()
        XCTAssertTrue(theme.waitForExistence(timeout: 5))
        XCTAssertEqual(theme.value as? String, "Stone & Amber")
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

        let firstResult = app.buttons["stub-cafe"]
        XCTAssertTrue(firstResult.waitForExistence(timeout: 15))
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
        app.launchArguments += arguments + ["-finishedOnboarding", "YES"]
        app.launch()
        return app
    }

    /// An app with its own profile store, so saved choices start empty; onboarded unless asked not to be.
    private func storedApp(arguments: [String], onboarded: Bool = true) -> XCUIApplication {
        let store = UUID().uuidString
        let app = XCUIApplication()
        app.launchArguments = arguments + (onboarded ? ["-finishedOnboarding.\(store)", "YES"] : [])
        app.launchEnvironment["SALIO_PROFILE_TEST_STORE"] = store
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
