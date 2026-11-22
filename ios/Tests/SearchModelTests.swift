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

    func testNearbyPrioritizesMatchesWithoutReorderingTextSearch() async {
        let cafe = StubPlaceSearcher.fixedPlaces[0]
        let cinema = StubPlaceSearcher.fixedPlaces[1]
        let unknown = LivePlace(id: "unknown", name: "Unknown", address: "", category: nil,
                                latitude: 51.518, longitude: -0.11)
        let bakery = LivePlace(id: "bakery", name: "Bakery", address: "", category: .bakery,
                               latitude: 51.520, longitude: -0.12)
        let original = [cinema, bakery, unknown, cafe]
        let model = SearchModel(searcher: StubPlaceSearcher(results: original))

        await model.loadNearby(near: cafe.coordinate, matching: [.cafe, .bakery])
        XCTAssertEqual(model.results.map(\.id), ["bakery", "stub-cafe", "stub-cinema", "unknown"])
        XCTAssertEqual(model.searchCount, 1)

        model.query = "coffee"
        await model.submit()
        XCTAssertEqual(model.results, original)
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
