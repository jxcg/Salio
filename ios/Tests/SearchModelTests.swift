import XCTest

@testable import Salio

@MainActor
final class SearchModelTests: XCTestCase {
    func testSubmitNonEmptyQueryRunsOneSearchAndShowsFixedResults() async throws {
        let model = SearchModel(searcher: StubPlaceSearcher(results: StubPlaceSearcher.fixedPlaces))
        model.query = "coffee"

        await model.submit()

        XCTAssertEqual(model.searchCount, 1)
        XCTAssertEqual(model.status, .results)
        XCTAssertEqual(model.results, StubPlaceSearcher.fixedPlaces)
    }

    func testEmptyQueryDoesNotRunSearch() async {
        let model = SearchModel(searcher: StubPlaceSearcher(results: StubPlaceSearcher.fixedPlaces))
        model.query = "   "

        await model.submit()

        XCTAssertEqual(model.searchCount, 0)
        XCTAssertEqual(model.status, .idle)
        XCTAssertTrue(model.results.isEmpty)
    }

    func testNearbyShowsOnlyChosenKindsNearestFirstAndTextSearchIsUnfiltered() async {
        let cafe = StubPlaceSearcher.fixedPlaces[0]
        let cinema = StubPlaceSearcher.fixedPlaces[1]
        let unknown = LivePlace(id: "unknown", name: "Unknown", address: "", category: nil,
                                latitude: 51.518, longitude: -0.11)
        let far = LivePlace(id: "far", name: "Far Kitchen", address: "", category: .restaurant,
                            latitude: 51.530, longitude: -0.13)
        let near = LivePlace(id: "near", name: "Near Market", address: "", category: .foodMarket,
                             latitude: 51.513, longitude: -0.13)
        let original = [far, cinema, unknown, near, cafe]
        let model = SearchModel(searcher: StubPlaceSearcher(results: original))

        await model.loadNearby(near: cafe.coordinate, kinds: ["Restaurants"])
        XCTAssertEqual(model.results.map(\.id), ["near", "far"])
        XCTAssertTrue(model.isNearbyResults)

        await model.loadNearby(near: cafe.coordinate, kinds: ["Film", "Cafés and bakeries"])
        XCTAssertEqual(model.results.map(\.id), ["stub-cafe", "stub-cinema"])

        await model.loadNearby(near: cafe.coordinate, kinds: [])
        XCTAssertEqual(model.results.first?.id, "stub-cafe")
        XCTAssertEqual(model.results.count, original.count)

        await model.loadNearby(near: cafe.coordinate, kinds: ["Bars and nightlife"])
        XCTAssertEqual(model.status, .empty)
        XCTAssertTrue(model.isNearbyResults)

        model.query = "coffee"
        await model.submit()
        XCTAssertEqual(model.results, original)
        XCTAssertFalse(model.isNearbyResults)
        XCTAssertEqual(model.searchCount, 5)
    }

    func testSavedInterestsFromBeforeKindsStillWork() {
        XCTAssertEqual(Preferences.kinds(from: ["Food", "Art"]), ["Restaurants", "Cafés and bakeries", "Culture"])
        XCTAssertEqual(Preferences.kinds(from: ["Film", "Outdoors", "Gone"]), ["Film", "Outdoors"])
        XCTAssertTrue(Preferences.categories(for: []).isEmpty)
        XCTAssertEqual(Set(Preferences.categories(for: ["Film"])), [.movieTheater])
    }

    func testSummaryShowsCategoryAndStreetInsteadOfFullAddress() {
        let place = LivePlace(id: "bar", name: "Bar Italia", address: "22 Frith Street, London, W1D 4RF, England",
                              category: .cafe, latitude: 51.5136, longitude: -0.1318)
        XCTAssertEqual(place.summary, "Café · 22 Frith Street")
        let bare = LivePlace(id: "bare", name: "Bare", address: "", category: nil, latitude: 0, longitude: 0)
        XCTAssertEqual(bare.summary, "")
    }

    func testEmptyResultShowsEmptyStatusAfterOneSearch() async {
        let model = SearchModel(searcher: StubPlaceSearcher(results: []))
        model.query = "coffee"

        await model.submit()

        XCTAssertEqual(model.searchCount, 1)
        XCTAssertEqual(model.status, .empty)
    }

    func testSearchErrorShowsFailedStatusAfterOneSearch() async {
        let model = SearchModel(searcher: StubPlaceSearcher(results: [], error: URLError(.badURL)))
        model.query = "coffee"

        await model.submit()

        XCTAssertEqual(model.searchCount, 1)
        XCTAssertEqual(model.status, .failed)
    }
}
