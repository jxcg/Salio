import MapKit
import os
import SwiftUI

@main
struct SalioApp: App {
    var body: some Scene {
        WindowGroup { FeedView() }
    }
}

struct FeedEntry: Identifiable {
    let id: String
    let name: String
    let category: String
    let walkMinutes: Int
    let closesAt: Date
    let leaveBy: Date

    static let samples: [FeedEntry] = {
        let demoStart = Date(timeIntervalSince1970: 1_893_520_800) // 2030-01-01 18:00 UTC
        return [
            FeedEntry(
                id: "cinema", name: "The Picture House", category: "Cinema", walkMinutes: 8,
                closesAt: demoStart.addingTimeInterval(79 * 60), leaveBy: demoStart.addingTimeInterval(11 * 60)
            ),
            FeedEntry(
                id: "gallery", name: "North Street Gallery", category: "Art", walkMinutes: 14,
                closesAt: demoStart.addingTimeInterval(154 * 60), leaveBy: demoStart.addingTimeInterval(80 * 60)
            ),
        ]
    }()
}

struct LivePlace: Identifiable, Equatable {
    let id: String
    let name: String
    let address: String
}

protocol PlaceSearching: Sendable {
    func search(_ query: String) async throws -> [LivePlace]
}

struct MapKitPlaceSearcher: PlaceSearching {
    func search(_ query: String) async throws -> [LivePlace] {
        #if DEBUG
        Logger(subsystem: Bundle.main.bundleIdentifier ?? "salio", category: "search").notice("MapKit search start")
        #endif
        var request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        let response = try await MKLocalSearch(request: request).start()
        return response.mapItems.compactMap { item in
            guard let name = item.name else { return nil }
            let coordinate = item.placemark.coordinate
            return LivePlace(
                id: "\(name)@\(coordinate.latitude),\(coordinate.longitude)",
                name: name,
                address: item.placemark.title ?? ""
            )
        }
    }
}

struct StubPlaceSearcher: PlaceSearching {
    static let fixedPlaces = [
        LivePlace(id: "stub-cafe", name: "Stub Café", address: "1 Stub Street"),
        LivePlace(id: "stub-cinema", name: "Stub Cinema", address: "2 Stub Street"),
    ]

    var results: [LivePlace]
    var error: (any Error)?

    func search(_ query: String) async throws -> [LivePlace] {
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

    func submit() async {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, status != .searching else { return }
        searchCount += 1
        status = .searching
        do {
            results = try await searcher.search(text)
            status = results.isEmpty ? .empty : .results
        } catch {
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
    private let entries = FeedEntry.samples
    @State private var selection: Selection?
    @State private var compactColumn: NavigationSplitViewColumn = .detail
    @State private var search = SearchModel(searcher: SearchModel.liveSearcher())

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
            List {
                Section {
                    TextField("Search places", text: $search.query, prompt: Text("Search places"))
                        .submitLabel(.search)
                        .onSubmit { Task { await search.submit() } }
                        .accessibilityIdentifier("search-field")
                }
                searchSections
                Section("Sample places") {
                    ForEach(entries) { entry in
                        sampleRow(entry)
                    }
                }
            }
            .navigationTitle("Nearby")
            .navigationBarBackButtonHidden()
        }
        .navigationSplitViewStyle(.balanced)
    }

    @ViewBuilder
    private var searchSections: some View {
        switch search.status {
        case .idle, .searching:
            EmptyView()
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
        #if DEBUG
        if showSearchCountInstrument {
            Section {
                Text("Searches: \(search.searchCount)")
                    .accessibilityIdentifier("search-count")
            }
        }
        #endif
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
        let selected = selectedLive?.id == place.id
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
                } footer: {
                    Text("Live results don’t include leave-by estimates.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Timing")
    }
}
