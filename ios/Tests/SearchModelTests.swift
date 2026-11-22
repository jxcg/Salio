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
