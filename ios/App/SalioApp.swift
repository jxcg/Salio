import CoreLocation
import MapKit
import os
import SwiftUI

@main
struct SalioApp: App {
    var body: some Scene {
        WindowGroup { FeedView() }
    }
}

struct FeedEntry: Decodable, Identifiable {
    let id: String
    let name: String
    let category: String
    let walkMinutes: Int
    let closesAt: Date
    let leaveBy: Date
}

struct LivePlace: Identifiable, Equatable {
    let id: String
    let name: String
    let address: String
    let latitude: Double
    let longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

enum PlaceRequest: Sendable {
    case nearby(CLLocationCoordinate2D)
    case text(String, near: CLLocationCoordinate2D?)
}

protocol PlaceSearching: Sendable {
    func search(_ request: PlaceRequest) async throws -> [LivePlace]
}

struct MapKitPlaceSearcher: PlaceSearching {
    private static let nearbyRadiusMeters: CLLocationDistance = 1_000
    private static let nearbyCategories: [MKPointOfInterestCategory] = [
        .cafe, .bakery, .restaurant, .brewery, .nightlife, .foodMarket,
        .museum, .movieTheater, .theater, .musicVenue, .landmark,
        .park, .beach, .zoo, .aquarium, .amusementPark,
    ]

    func search(_ request: PlaceRequest) async throws -> [LivePlace] {
        #if DEBUG
        Logger(subsystem: Bundle.main.bundleIdentifier ?? "salio", category: "search").notice("MapKit search start")
        #endif
        let search: MKLocalSearch
        switch request {
        case .nearby(let center):
            let request = MKLocalPointsOfInterestRequest(center: center, radius: Self.nearbyRadiusMeters)
            request.pointOfInterestFilter = MKPointOfInterestFilter(including: Self.nearbyCategories)
            search = MKLocalSearch(request: request)
        case .text(let query, let center):
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            if let center {
                let span = Self.nearbyRadiusMeters * 2
                request.region = MKCoordinateRegion(center: center, latitudinalMeters: span, longitudinalMeters: span)
            }
            search = MKLocalSearch(request: request)
        }
        let response = try await search.start()
        var seen = Set<LivePlace.ID>()
        return response.mapItems.compactMap { item in
            guard let name = item.name else { return nil }
            let coordinate: CLLocationCoordinate2D
            let address: String
            if #available(iOS 26, *) {
                coordinate = item.location.coordinate
                address = item.address?.fullAddress ?? ""
            } else {
                coordinate = item.placemark.coordinate
                address = item.placemark.title ?? ""
            }
            let id = item.identifier?.rawValue ?? "\(name)@\(coordinate.latitude),\(coordinate.longitude)"
            guard seen.insert(id).inserted else { return nil }
            return LivePlace(
                id: id,
                name: name,
                address: address,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )
        }
    }
}

struct StubPlaceSearcher: PlaceSearching {
    static let fixedPlaces = [
        LivePlace(id: "stub-cafe", name: "Stub Café", address: "1 Stub Street", latitude: 51.5128, longitude: -0.1300),
        LivePlace(id: "stub-cinema", name: "Stub Cinema", address: "2 Stub Street", latitude: 51.5160, longitude: -0.1238),
    ]

    var results: [LivePlace]
    var error: (any Error)?

    func search(_ request: PlaceRequest) async throws -> [LivePlace] {
        if let error { throw error }
        return results
    }
}

@MainActor
@Observable
final class SearchModel {
    enum Status: Equatable {
        case idle
        case searching
        case results
        case empty
        case failed
    }

    var query = ""
    private(set) var status: Status = .idle
    private(set) var results: [LivePlace] = []
    private(set) var searchCount = 0

    private let searcher: any PlaceSearching

    init(searcher: any PlaceSearching) {
        self.searcher = searcher
    }

    func submit(near center: CLLocationCoordinate2D? = nil) async {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        await load(.text(text, near: center))
    }

    func load(_ request: PlaceRequest) async {
        guard status != .searching else { return }
        searchCount += 1
        status = .searching
        do {
            results = try await searcher.search(request)
            status = results.isEmpty ? .empty : .results
        } catch {
            results = []
            status = .failed
        }
    }

    static func liveSearcher() -> any PlaceSearching {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-SALIOStubSearchEmpty") {
            return StubPlaceSearcher(results: [], error: nil)
        }
        if arguments.contains("-SALIOStubSearchError") {
            return StubPlaceSearcher(results: [], error: URLError(.badURL))
        }
        if arguments.contains("-SALIOStubSearch") {
            return StubPlaceSearcher(results: StubPlaceSearcher.fixedPlaces, error: nil)
        }
        return MapKitPlaceSearcher()
    }
}

private enum Selection: Hashable {
    case sample(FeedEntry.ID)
    case live(LivePlace.ID)
}

private struct FeedView: View {
    @State private var entries: [FeedEntry] = []
    @State private var sampleFailed = false
    @State private var selection: Selection?
    @State private var compactColumn: NavigationSplitViewColumn = .detail
    @State private var search = SearchModel(searcher: SearchModel.liveSearcher())
    @State private var center: CLLocationCoordinate2D?
    @State private var locating = false
    @State private var didLocate = false
    @State private var showMap = false
    @State private var camera: MapCameraPosition = .automatic

    private var selectedSample: FeedEntry? {
        if let selection, case .sample(let id) = selection, let entry = entries.first(where: { $0.id == id }) {
            return entry
        }
        return selection == nil ? entries.first : nil
    }

    private var selectedLive: LivePlace? {
        guard case .live(let id) = selection else { return nil }
        return search.results.first { $0.id == id }
    }

    var body: some View {
        NavigationSplitView(preferredCompactColumn: $compactColumn) {
            placeContext
        } detail: {
            Group {
                if showMap, search.status == .results {
                    placesMap
                        .safeAreaInset(edge: .bottom) {
                            if let place = selectedLive {
                                rowLabel(title: place.name, subtitle: place.address, leaveBy: nil, selected: false)
                                    .padding(.horizontal)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(.regularMaterial)
                            }
                        }
                } else {
                    placeList
                }
            }
            .navigationBarBackButtonHidden()
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if !showMap, center != nil {
                        Button("Refresh nearby", systemImage: "arrow.clockwise") {
                            Task { await locate(initial: false) }
                        }
                        .disabled(locating || search.status == .searching)
                        .accessibilityIdentifier("refresh-nearby")
                    }
                    if search.status == .results {
                        Button(showMap ? "Show list" : "Show map", systemImage: showMap ? "list.bullet" : "map") {
                            showMap.toggle()
                        }
                        .accessibilityIdentifier(showMap ? "show-list" : "show-map")
                    }
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .task { await loadSamples() }
        .task { await locate(initial: true) }
        .onChange(of: search.results) {
            camera = .automatic
        }
    }

    private var placeList: some View {
        List {
            Section {
                TextField("Search places", text: $search.query, prompt: Text("Search places"))
                    .submitLabel(.search)
                    .onSubmit { Task { await search.submit(near: center) } }
                    .disabled(search.status == .searching)
                    .accessibilityIdentifier("search-field")
            }
            if showSearchCountInstrument {
                Text("Searches: \(search.searchCount)")
                    .accessibilityIdentifier("search-count")
            }
            searchSections
            if !entries.isEmpty || sampleFailed {
                Section("Sample places") {
                    if sampleFailed {
                        Text("Can’t load sample places.").foregroundStyle(.secondary)
                    }
                    ForEach(entries) { entry in
                        sampleRow(entry)
                    }
                }
            }
        }
    }

    private var placesMap: some View {
        Map(position: $camera) {
            ForEach(search.results) { place in
                let selected = selection == .live(place.id)
                let color: Color = selected ? .accentColor : .red
                Annotation(place.name, coordinate: place.coordinate) {
                    Button {
                        selection = .live(place.id)
                    } label: {
                        Image(systemName: "mappin.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white, color)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(place.name)
                    .accessibilityIdentifier("pin-\(place.id)")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
    }

    @ViewBuilder
    private var searchSections: some View {
        switch search.status {
        case .idle:
            if locating {
                ProgressView("Finding your location…")
            } else {
                Text("Search places or turn on location to see what’s nearby.")
                    .foregroundStyle(.secondary)
            }
        case .searching:
            ProgressView("Finding places…")
        case .results:
            Section("Results") {
                ForEach(search.results) { place in
                    liveRow(place)
                }
            }
        case .empty:
            Section {
                Text("No matches. Try a different search.")
                    .foregroundStyle(.secondary)
            }
        case .failed:
            Section {
                Text("Can’t search right now. Try again.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var showSearchCountInstrument: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-SALIOShowSearchCount")
        #else
        false
        #endif
    }

    private func sampleRow(_ entry: FeedEntry) -> some View {
        let selected = selectedSample?.id == entry.id
        return Button {
            selection = .sample(entry.id)
        } label: {
            rowLabel(
                title: entry.name,
                subtitle: "\(entry.category) · \(entry.walkMinutes) min walk",
                leaveBy: entry.leaveBy,
                selected: selected
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func liveRow(_ place: LivePlace) -> some View {
        let selected = selection == .live(place.id)
        return Button {
            selection = .live(place.id)
        } label: {
            rowLabel(title: place.name, subtitle: place.address, leaveBy: nil, selected: selected)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(place.id)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func rowLabel(title: String, subtitle: String, leaveBy: Date?, selected: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                Text(subtitle).foregroundStyle(.secondary)
                if let leaveBy {
                    Label {
                        Text("Leave by \(leaveBy.formatted(date: .omitted, time: .shortened))")
                    } icon: {
                        Image(systemName: "clock")
                    }
                    .font(.subheadline.weight(.medium))
                }
            }
            Spacer(minLength: 8)
            if selected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var placeContext: some View {
        List {
            if let sample = selectedSample {
                Section {
                    Text(sample.name).font(.headline)
                    LabeledContent("Walk", value: "\(sample.walkMinutes) min")
                    LabeledContent("Closes", value: sample.closesAt.formatted(date: .omitted, time: .shortened))
                } footer: {
                    Text("Your leave-by time includes the walk and an hour at the venue before it closes.")
                }
            } else if let live = selectedLive {
                Section {
                    Text(live.name).font(.headline)
                    LabeledContent("Address", value: live.address)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(selectedSample == nil ? "Place details" : "Timing")
    }

    private func locate(initial: Bool) async {
        guard !locating, !initial || !didLocate else { return }
        let searchCount = search.searchCount
        locating = true
        defer { locating = false }
        center = await currentLocation()
        guard !Task.isCancelled else { return }
        didLocate = true
        guard let center, search.searchCount == searchCount, !initial || searchCount == 0 else { return }
        if !initial { search.query = "" }
        await search.load(.nearby(center))
    }

    private func currentLocation() async -> CLLocationCoordinate2D? {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-SALIOStubLocation") {
            return StubPlaceSearcher.fixedPlaces[0].coordinate
        }
        if arguments.contains(where: { $0.hasPrefix("-SALIOStubSearch") }) { return nil }
        #endif
        do {
            for try await update in CLLocationUpdate.liveUpdates() {
                if let location = update.location { return location.coordinate }
                if update.authorizationDenied || update.authorizationDeniedGlobally || update.authorizationRestricted {
                    break
                }
            }
        } catch {
            return nil
        }
        return nil
    }

    private func loadSamples() async {
        guard let value = ProcessInfo.processInfo.environment["SALIO_API_URL"],
              let baseURL = URL(string: value) else { return }
        do {
            let url = baseURL.appending(components: "v1", "sample-feed")
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            decoder.dateDecodingStrategy = .iso8601
            entries = try decoder.decode([FeedEntry].self, from: data)
        } catch {
            sampleFailed = true
        }
    }
}
