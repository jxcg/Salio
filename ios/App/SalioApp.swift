import CoreLocation
import MapKit
import os
import SwiftData
import SwiftUI

@main
struct SalioApp: App {
    private let profileContainer = Result {
        try ModelContainer(for: Preferences.self, configurations: Self.profileStore)
    }

    var body: some Scene {
        WindowGroup { FeedView(profileContainer: profileContainer) }
    }

    private static var profileStore: ModelConfiguration {
        #if DEBUG
        if let name = ProcessInfo.processInfo.environment["SALIO_PROFILE_TEST_STORE"] {
            return ModelConfiguration(name, cloudKitDatabase: .none)
        }
        #endif
        return ModelConfiguration(cloudKitDatabase: .none)
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
    let category: MKPointOfInterestCategory?
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
                category: item.pointOfInterestCategory,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )
        }
    }
}

struct StubPlaceSearcher: PlaceSearching {
    static let fixedPlaces = [
        LivePlace(id: "stub-cafe", name: "Stub Café", address: "1 Stub Street", category: .cafe,
                  latitude: 51.5128, longitude: -0.1300),
        LivePlace(id: "stub-cinema", name: "Stub Cinema", address: "2 Stub Street", category: .movieTheater,
                  latitude: 51.5160, longitude: -0.1238),
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
    private(set) var isNearbyResults = false
    private(set) var searchCount = 0

    private let searcher: any PlaceSearching
    private var rawNearbyResults: [LivePlace] = []

    init(searcher: any PlaceSearching) {
        self.searcher = searcher
    }

    func submit(near center: CLLocationCoordinate2D? = nil) async {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        await load(.text(text, near: center), nearby: false, interests: [])
    }

    func loadNearby(near center: CLLocationCoordinate2D, matching interests: [String]) async {
        await load(.nearby(center), nearby: true, interests: interests)
    }

    func reprioritize(for interests: [String]) {
        guard isNearbyResults else { return }
        results = Self.prioritized(rawNearbyResults, for: interests)
    }

    func matchReason(for place: LivePlace, interests: [String]) -> String? {
        guard isNearbyResults,
              let interest = Preferences.matchingInterest(for: place.category, in: interests) else { return nil }
        return "Matches \(interest)"
    }

    private func load(_ request: PlaceRequest, nearby: Bool, interests: [String]) async {
        guard status != .searching else { return }
        searchCount += 1
        status = .searching
        do {
            let places = try await searcher.search(request)
            isNearbyResults = nearby
            rawNearbyResults = nearby ? places : []
            results = nearby ? Self.prioritized(places, for: interests) : places
            status = results.isEmpty ? .empty : .results
        } catch {
            isNearbyResults = false
            rawNearbyResults = []
            results = []
            status = .failed
        }
    }

    private static func prioritized(_ places: [LivePlace], for interests: [String]) -> [LivePlace] {
        guard !interests.isEmpty else { return places }
        var matches: [LivePlace] = []
        var others: [LivePlace] = []
        for place in places {
            if Preferences.matchingInterest(for: place.category, in: interests) != nil {
                matches.append(place)
            } else {
                others.append(place)
            }
        }
        return matches + others
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
    private enum ProfileSheet: String, Identifiable {
        case onboarding, profile
        var id: String { rawValue }
    }

    let profileContainer: Result<ModelContainer, any Error>
    private let entries = FeedEntry.samples
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @AppStorage(SalioAppearance.storageKey) private var appearance: SalioAppearance = .mistGlass
    @State private var selection: Selection?
    @State private var compactColumn: NavigationSplitViewColumn = .detail
    @State private var search = SearchModel(searcher: SearchModel.liveSearcher())
    @State private var wasClosed = false
    @State private var hingeOpen = false
    @State private var showContextCue = false
    @State private var profileSheet: ProfileSheet?
    @AppStorage(Self.interestSetupKey) private var finishedInterestSetup = false
    @State private var activeInterests: [String] = []
    @State private var center: CLLocationCoordinate2D?
    @State private var locating = false
    @State private var didLocate = false
    @State private var showMap = false
    @State private var camera: MapCameraPosition = .automatic
    @State private var rippleStart: Date?
    @State private var rippleOrigin = UnitPoint(x: 0.62, y: 0.42)

    private var palette: SalioPalette {
        appearance.palette(for: colorScheme)
    }

    private func triggerRipple(at origin: UnitPoint = UnitPoint(x: 0.62, y: 0.42)) {
        rippleOrigin = origin
        rippleStart = Date()
    }

    private static var interestSetupKey: String {
        #if DEBUG
        if let store = ProcessInfo.processInfo.environment["SALIO_PROFILE_TEST_STORE"] {
            return "finishedInterestSetup.\(store)"
        }
        #endif
        return "finishedInterestSetup"
    }

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

    private var allowsContextCue: Bool {
        !reduceMotion && !voiceOver && contrast != .increased
    }

    @ViewBuilder var body: some View {
        // Build without hinge support on toolchains that predate the Duo SDK.
        #if compiler(>=6.4.2)
        if #available(iOS 27.1, *) {
            splitView.onHingeChange { old, new in
                let status = new.hinge?.status
                guard old.hinge?.status != status else { return }
                hingeOpen = status == .fullyOpen
                showContextCue = hingeOpen && wasClosed && allowsContextCue
                if status == .closed {
                    wasClosed = true
                } else if status == .fullyOpen || status == nil {
                    wasClosed = false
                }
            }
            .task(id: showContextCue) {
                guard showContextCue else { return }
                do {
                    try await Task.sleep(for: .milliseconds(25))
                    withAnimation(.easeOut(duration: 0.125)) { showContextCue = false }
                } catch {
                    // Closing cancels the cue; there is nothing to finish.
                }
            }
        } else {
            splitView
        }
        #else
        splitView
        #endif
    }

    private var splitView: some View {
        NavigationSplitView(preferredCompactColumn: $compactColumn) {
            placeContext
        } detail: {
            Group {
                if showMap, search.status == .results {
                    placesMap
                        .safeAreaInset(edge: .bottom) {
                            if let place = selectedLive {
                                FrostedGlassCard(
                                    palette: palette,
                                    rippleStart: rippleStart,
                                    rippleOrigin: rippleOrigin
                                ) {
                                    featuredPlaceContent(
                                        title: place.name,
                                        subtitle: place.address,
                                        reason: search.matchReason(for: place, interests: activeInterests),
                                        selected: true
                                    )
                                }
                                .padding(.horizontal, 16)
                                .padding(.bottom, 8)
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
                            triggerRipple()
                            Task { await locate(initial: false) }
                        }
                        .disabled(locating || search.status == .searching)
                        .accessibilityIdentifier("refresh-nearby")
                    }
                    if search.status == .results {
                        Button(showMap ? "Show list" : "Show map", systemImage: showMap ? "list.bullet" : "map") {
                            showMap.toggle()
                            triggerRipple()
                        }
                        .accessibilityIdentifier(showMap ? "show-list" : "show-map")
                    }
                    Button("Profile", systemImage: "person.crop.circle") { profileSheet = .profile }
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .tint(palette.signal)
        .sheet(item: $profileSheet) { sheet in
            switch profileContainer {
            case .success(let container):
                ProfileView(
                    interestsOnly: sheet == .onboarding,
                    onSave: { interests in
                        finishedInterestSetup = true
                        activeInterests = interests
                        search.reprioritize(for: interests)
                        triggerRipple(at: UnitPoint(x: 0.50, y: 0.44))
                    },
                    onReset: {
                        activeInterests = []
                        search.reprioritize(for: [])
                        triggerRipple(at: UnitPoint(x: 0.50, y: 0.44))
                    }
                )
                .modelContainer(container)
            case .failure: ContentUnavailableView("Profile unavailable", systemImage: "person.crop.circle")
            }
        }
        .task { await locate(initial: true) }
        .onChange(of: search.results) {
            camera = .automatic
            triggerRipple()
        }
        .onChange(of: appearance) {
            triggerRipple()
        }
    }

    private var placeList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(palette.muted)
                        .accessibilityHidden(true)
                    TextField(
                        "Search places",
                        text: $search.query,
                        prompt: Text("Search places").foregroundStyle(palette.muted)
                    )
                    .foregroundStyle(palette.ink)
                    .submitLabel(.search)
                    .onSubmit {
                        triggerRipple()
                        Task { await search.submit(near: center) }
                    }
                    .disabled(search.status == .searching)
                    .accessibilityIdentifier("search-field")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(palette.card, in: Capsule())
                .overlay(Capsule().strokeBorder(palette.border, lineWidth: 1))

                if showSearchCountInstrument {
                    Text("Searches: \(search.searchCount)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(palette.muted)
                        .accessibilityIdentifier("search-count")
                }

                searchSections

                if !finishedInterestSetup, case .success = profileContainer {
                    FrostedGlassCard(
                        palette: palette,
                        rippleStart: rippleStart,
                        rippleOrigin: rippleOrigin
                    ) {
                        VStack(alignment: .leading, spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Make it yours")
                                    .font(.headline.weight(.bold))
                                    .foregroundStyle(palette.ink)
                                Text("Choose what you like to see matching places first.")
                                    .font(.subheadline)
                                    .foregroundStyle(palette.muted)
                            }
                            HStack(spacing: 8) {
                                Button("Choose interests") {
                                    triggerRipple(at: UnitPoint(x: 0.30, y: 0.72))
                                    profileSheet = .onboarding
                                }
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(palette.onCTA)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(palette.ink, in: Capsule())
                                .buttonStyle(.plain)

                                Button("Skip for now") {
                                    finishedInterestSetup = true
                                }
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(palette.ink)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(palette.soft, in: Capsule())
                                .buttonStyle(.plain)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Sample places")
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(palette.muted)
                        .padding(.horizontal, 4)

                    VStack(spacing: 0) {
                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                            if index > 0 {
                                Divider().overlay(palette.border)
                                    .padding(.leading, 16)
                            }
                            sampleRow(entry)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 6)
                        }
                    }
                    .background(palette.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(palette.border, lineWidth: 1)
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
        .background(palette.ground.ignoresSafeArea())
    }

    private var placesMap: some View {
        Map(position: $camera) {
            ForEach(search.results) { place in
                let selected = selection == .live(place.id)
                let color: Color = selected ? palette.signal : palette.ink
                Annotation(place.name, coordinate: place.coordinate) {
                    Button {
                        selection = .live(place.id)
                        triggerRipple(at: UnitPoint(x: 0.50, y: 0.45))
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
            statusCard {
                if locating {
                    ProgressView("Finding your location…")
                        .tint(palette.signal)
                        .foregroundStyle(palette.muted)
                } else {
                    Text("Search places or turn on location to see what’s nearby.")
                        .font(.subheadline)
                        .foregroundStyle(palette.muted)
                }
            }
        case .searching:
            statusCard {
                ProgressView("Finding places…")
                    .tint(palette.signal)
                    .foregroundStyle(palette.muted)
            }
        case .results:
            VStack(alignment: .leading, spacing: 10) {
                Text("Results")
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(palette.muted)
                    .padding(.horizontal, 4)

                if let featured = search.results.first {
                    featuredLiveRow(featured)
                }

                let remaining = Array(search.results.dropFirst())
                if !remaining.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(remaining.enumerated()), id: \.element.id) { index, place in
                            if index > 0 {
                                Divider().overlay(palette.border)
                                    .padding(.leading, 16)
                            }
                            liveRow(place)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 6)
                        }
                    }
                    .background(palette.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(palette.border, lineWidth: 1)
                    )
                }
            }
        case .empty:
            statusCard {
                Text("No matches. Try a different search.")
                    .font(.subheadline)
                    .foregroundStyle(palette.muted)
            }
        case .failed:
            statusCard {
                Text("Can’t search right now. Try again.")
                    .font(.subheadline)
                    .foregroundStyle(palette.muted)
            }
        }
    }

    private func statusCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(palette.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(palette.border, lineWidth: 1)
            )
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
            triggerRipple()
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

    private func featuredLiveRow(_ place: LivePlace) -> some View {
        let selected = selection == .live(place.id)
        return Button {
            selection = .live(place.id)
            triggerRipple(at: UnitPoint(x: 0.55, y: 0.48))
        } label: {
            FrostedGlassCard(
                palette: palette,
                rippleStart: rippleStart,
                rippleOrigin: rippleOrigin
            ) {
                featuredPlaceContent(
                    title: place.name,
                    subtitle: place.address,
                    reason: search.matchReason(for: place, interests: activeInterests),
                    selected: selected
                )
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(place.id)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func featuredPlaceContent(title: String, subtitle: String, reason: String?, selected: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                if let reason {
                    Text(reason)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(palette.signal)
                }
                Text(title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(palette.ink)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(palette.muted)
                }
            }
            Spacer(minLength: 8)
            if selected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(palette.signal)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func liveRow(_ place: LivePlace) -> some View {
        let selected = selection == .live(place.id)
        return Button {
            selection = .live(place.id)
            triggerRipple()
        } label: {
            rowLabel(
                title: place.name,
                subtitle: place.address,
                reason: search.matchReason(for: place, interests: activeInterests),
                leaveBy: nil,
                selected: selected
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(place.id)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func rowLabel(title: String, subtitle: String, reason: String? = nil, leaveBy: Date?, selected: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(palette.ink)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(palette.muted)
                if let reason {
                    Text(reason)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(palette.signal)
                }
                if let leaveBy {
                    Label {
                        Text("Leave by \(leaveBy.formatted(date: .omitted, time: .shortened))")
                            .monospacedDigit()
                    } icon: {
                        Image(systemName: "clock")
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(palette.leaveBy)
                }
            }
            Spacer(minLength: 8)
            if selected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(palette.signal)
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
                    contextTitle(sample.name)
                    LabeledContent("Walk", value: "\(sample.walkMinutes) min")
                    LabeledContent("Closes", value: sample.closesAt.formatted(date: .omitted, time: .shortened))
                } footer: {
                    Text("Your leave-by time includes the walk and an hour at the venue before it closes.")
                }
                .listRowBackground(palette.card)
            } else if let live = selectedLive {
                Section {
                    contextTitle(live.name)
                    LabeledContent("Address", value: live.address)
                    if let reason = search.matchReason(for: live, interests: activeInterests) {
                        LabeledContent("Why it’s here", value: reason)
                    }
                }
                .listRowBackground(palette.card)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(palette.ground)
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
        let interests = (try? profileContainer.get().mainContext.fetch(FetchDescriptor<Preferences>()).first?.interests) ?? []
        activeInterests = interests
        await search.loadNearby(near: center, matching: interests)
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

    private func contextTitle(_ name: String) -> some View {
        Text(name).font(.headline)
            .overlay(alignment: .leading) {
                ZStack {
                    if showContextCue {
                        Rectangle()
                            .fill(palette.signal.opacity(0.18))
                            .frame(width: 2, height: 18)
                            .colorEffect(ShaderLibrary.contextAccent(.boundingRect))
                            .offset(x: -6)
                            .transition(.asymmetric(insertion: .identity, removal: .opacity))
                    }
                }
                .opacity(hingeOpen && allowsContextCue ? 1 : 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
    }
}
