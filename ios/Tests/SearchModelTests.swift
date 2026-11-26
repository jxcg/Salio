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

    func testNearbyPutsMatchesFirstNearestFirstReprioritizesLocallyAndLeavesTextSearchUntouched() async {
        let cafe = StubPlaceSearcher.fixedPlaces[0]
        let cinema = StubPlaceSearcher.fixedPlaces[1]
        let unknown = LivePlace(id: "unknown", name: "Unknown", address: "", category: nil,
                                latitude: 51.518, longitude: -0.11)
        let bakery = LivePlace(id: "bakery", name: "Bakery", address: "", category: .bakery,
                               latitude: 51.520, longitude: -0.12)
        let original = [cinema, bakery, unknown, cafe]
        let model = SearchModel(searcher: StubPlaceSearcher(results: original))

        await model.loadNearby(near: cafe.coordinate, matching: ["Food"])
        XCTAssertEqual(model.results.map(\.id), ["stub-cafe", "bakery", "stub-cinema", "unknown"])
        XCTAssertEqual(model.matchReason(for: bakery, interests: ["Food"]), "Matches Food")
        XCTAssertNil(model.matchReason(for: cinema, interests: ["Food"]))
        XCTAssertNil(model.matchReason(for: unknown, interests: ["Food"]))
        XCTAssertEqual(model.searchCount, 1)

        model.reprioritize(for: ["Film"])
        XCTAssertEqual(model.results.map(\.id), ["stub-cinema", "stub-cafe", "bakery", "unknown"])
        XCTAssertEqual(model.matchReason(for: cinema, interests: ["Film"]), "Matches Film")
        XCTAssertNil(model.matchReason(for: bakery, interests: ["Film"]))
        XCTAssertEqual(model.searchCount, 1)

        model.reprioritize(for: [])
        XCTAssertEqual(model.results.map(\.id), ["stub-cafe", "stub-cinema", "bakery", "unknown"])
        XCTAssertEqual(model.searchCount, 1)

        model.query = "coffee"
        await model.submit()
        XCTAssertEqual(model.results, original)
        XCTAssertNil(model.matchReason(for: cinema, interests: ["Film"]))
        model.reprioritize(for: ["Food"])
        XCTAssertEqual(model.results, original)
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
