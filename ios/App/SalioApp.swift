import CoreLocation
import MapKit
import SwiftData
import SwiftUI

@main
struct SalioApp: App {
    private let profileContainer = Result {
        try ModelContainer(for: Preferences.self, configurations: Self.profileStore)
    }

    /// App state survives backgrounding, so the opening plays on cold launches only.
    @State private var showsOpening = true
    @State private var feedReady = false
    @State private var feedFound = false

    var body: some Scene {
        WindowGroup {
            FeedView(profileContainer: profileContainer) { found in
                feedFound = found
                feedReady = true
            }
                .overlay {
                    if showsOpening { SalioOpening(ready: feedReady, found: feedFound) { showsOpening = false } }
                }
        }
    }

    private static var profileStore: ModelConfiguration {
        if let name = SalioTestStore.name {
            return ModelConfiguration(name, cloudKitDatabase: .none)
        }
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
    let latitude: Double
    let longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    static let samples: [FeedEntry] = {
        let demoStart = Date(timeIntervalSince1970: 1_893_520_800) // 2030-01-01 18:00 UTC
        return [
            FeedEntry(
                id: "cinema", name: "The Picture House", category: "Cinema", walkMinutes: 8,
                closesAt: demoStart.addingTimeInterval(79 * 60), leaveBy: demoStart.addingTimeInterval(11 * 60),
                latitude: 51.5136, longitude: -0.1365
            ),
            FeedEntry(
                id: "gallery", name: "North Street Gallery", category: "Art", walkMinutes: 14,
                closesAt: demoStart.addingTimeInterval(154 * 60), leaveBy: demoStart.addingTimeInterval(80 * 60),
                latitude: 51.5150, longitude: -0.1318
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

    /// Category and street, such as "Café · 22 Frith Street", instead of the full postal address.
    var summary: String {
        let street = address.split(separator: ",").first.map { $0.trimmingCharacters(in: .whitespaces) }
        return [category?.displayName, street].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// Straight-line distance, worked out on the device.
    func distance(from center: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: latitude, longitude: longitude)
            .distance(from: CLLocation(latitude: center.latitude, longitude: center.longitude))
    }
}

extension MKPointOfInterestCategory {
    var displayName: String? {
        switch self {
        case .cafe: "Café"
        case .bakery: "Bakery"
        case .restaurant: "Restaurant"
        case .brewery: "Brewery"
        case .nightlife: "Nightlife"
        case .foodMarket: "Food market"
        case .museum: "Museum"
        case .movieTheater: "Cinema"
        case .theater: "Theatre"
        case .musicVenue: "Music venue"
        case .landmark: "Landmark"
        case .park: "Park"
        case .beach: "Beach"
        case .zoo: "Zoo"
        case .aquarium: "Aquarium"
        case .amusementPark: "Theme park"
        default: nil
        }
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
    enum Status {
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
    private var nearbyCenter: CLLocationCoordinate2D?

    init(searcher: any PlaceSearching) {
        self.searcher = searcher
    }

    func submit(near center: CLLocationCoordinate2D? = nil) async {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        await load(.text(text, near: center), nearby: false, interests: [])
    }

    func loadNearby(near center: CLLocationCoordinate2D, matching interests: [String]) async {
        nearbyCenter = center
        await load(.nearby(center), nearby: true, interests: interests)
    }

    func reprioritize(for interests: [String]) {
        guard isNearbyResults else { return }
        results = Self.prioritized(rawNearbyResults, for: interests, near: nearbyCenter)
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
            results = nearby ? Self.prioritized(places, for: interests, near: nearbyCenter) : places
            status = results.isEmpty ? .empty : .results
        } catch {
            isNearbyResults = false
            rawNearbyResults = []
            results = []
            status = .failed
        }
    }

    /// Interest matches first, and each group nearest first.
    private static func prioritized(
        _ places: [LivePlace],
        for interests: [String],
        near center: CLLocationCoordinate2D?
    ) -> [LivePlace] {
        let ordered = center.map { center in
            places.sorted { $0.distance(from: center) < $1.distance(from: center) }
        } ?? places
        guard !interests.isEmpty else { return ordered }
        var matches: [LivePlace] = []
        var others: [LivePlace] = []
        for place in ordered {
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

#if compiler(>=6.4.2)
/// Reads the hinge angle from UIKit, which SwiftUI's `onHingeChange` doesn't expose, and turns how fast
/// it's moving into how frosted the Duo's left page should be: 0 is clear, 1 is fully frosted.
@available(iOS 27.1, *)
private struct HingeReader: UIViewRepresentable {
    /// Called with the frost amount and the animation to reach it.
    let onFrost: (Double, Animation) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        let coordinator = context.coordinator
        view.addInteraction(UIHingeInteraction { _, update in
            MainActor.assumeIsolated { coordinator.update(update.hinge) }
        })
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.onFrost = onFrost
    }

    @MainActor
    final class Coordinator {
        /// How long the angle must hold still before the frost clears.
        static let restDelay: Duration = .milliseconds(200)
        /// Angle changes under about half a degree are sensor noise, not motion.
        static let jitter: CGFloat = 0.009
        /// Hinge speed that frosts the page fully, in radians a second (about 115° a second).
        static let fullFrostSpeed = 2.0

        var onFrost: (Double, Animation) -> Void = { _, _ in }
        private var lastMove: (angle: CGFloat, time: ContinuousClock.Instant)?
        private var speed = 0.0
        private var rest: Task<Void, Never>?

        func update(_ hinge: UIHinge?) {
            guard let hinge, hinge.status != .closed else {
                stop()
                onFrost(hinge == nil ? 0 : 1, .easeOut(duration: 0.2))
                return
            }
            let now = ContinuousClock.now
            guard let lastMove else {
                lastMove = (hinge.angle, now)
                clearWhenStill()
                return
            }
            // Measure from the last real move, so slow turns add up past the noise threshold.
            let delta = abs(hinge.angle - lastMove.angle)
            guard delta > Self.jitter else { return }
            let elapsed = now - lastMove.time
            let seconds = max(Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18, 1 / 120)
            speed = speed * 0.5 + Double(delta) / seconds * 0.5
            self.lastMove = (hinge.angle, now)
            onFrost(min(1, speed / Self.fullFrostSpeed), .linear(duration: 0.12))
            clearWhenStill()
        }

        private func clearWhenStill() {
            rest?.cancel()
            rest = Task { [weak self] in
                try? await Task.sleep(for: Self.restDelay)
                guard let self, !Task.isCancelled else { return }
                speed = 0
                onFrost(0, .easeInOut(duration: 0.35))
            }
        }

        private func stop() {
            rest?.cancel()
            lastMove = nil
            speed = 0
        }
    }
}
#endif

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
    /// Called once the first Nearby load has finished, with whether it found places. It is also called
    /// when the load failed, found nothing, or had no location.
    var onFirstLoad: (_ found: Bool) -> Void = { _ in }
    private let entries = FeedEntry.samples
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.openURL) private var openURL
    @AppStorage(SalioAppearance.storageKey) private var appearance: SalioAppearance = .mistGlass
    @State private var selection: Selection?
    @State private var compactColumn: NavigationSplitViewColumn = .detail
    @State private var search = SearchModel(searcher: SearchModel.liveSearcher())
    @State private var profileSheet: ProfileSheet?
    @AppStorage(SalioTestStore.scopedKey("finishedInterestSetup")) private var finishedInterestSetup = false
    @State private var activeInterests: [String] = []
    @State private var center: CLLocationCoordinate2D?
    @State private var locating = false
    @State private var didLocate = false
    @State private var showMap = false
    @State private var camera: MapCameraPosition = .automatic
    @State private var railCamera: MapCameraPosition = .automatic
    @State private var featuredCardRipple = 0
    @State private var mapCardRipple = 0
    /// How frosted the Duo's left page is, from 0 (clear) to 1, following how fast the hinge moves.
    @State private var railFrost = 0.0
    @State private var compactFeedWidth: CGFloat?
    /// Width from the window's leading edge to the Duo fold, so the inner display splits like an open book.
    @State private var foldOffset: CGFloat?

    private var palette: SalioPalette {
        appearance.palette(for: colorScheme)
    }

    private var railMapRevealKey: String {
        if let live = selectedLive { return "live-\(live.id)" }
        if let sample = selectedSample { return "sample-\(sample.id)" }
        return "initial"
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

    private var allowsUnfoldMotion: Bool {
        !reduceMotion && !voiceOver && contrast != .increased
    }

    @ViewBuilder var body: some View {
        // Build without hinge support on toolchains that predate the Duo SDK.
        #if compiler(>=6.4.2)
        if #available(iOS 27.1, *) {
            splitView
                .background {
                    HingeReader { frost, animation in
                        withAnimation(animation) { railFrost = frost }
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
        Group {
            if let foldOffset {
                // Open Duo: two pages meet at the fold, and the right page keeps the cover's feed.
                HStack(spacing: 0) {
                    let frost = allowsUnfoldMotion ? railFrost : 0
                    let frosted = frost > 0.05
                    NavigationStack {
                        placeContext.navigationBarTitleDisplayMode(.inline)
                    }
                    .accessibilityHidden(frosted)
                    // One frosted layer over the whole left page, title and map included, as thick as the hinge is fast.
                    .overlay {
                        Rectangle()
                            .fill(.thinMaterial)
                            .opacity(frost)
                            .ignoresSafeArea()
                            .allowsHitTesting(frosted)
                            .accessibilityHidden(true)
                    }
                    .frame(width: foldOffset)
                    // Nothing on the left page, ASCII veil included, may draw past the fold while folding.
                    // The mask runs full height so the page can still reach under the status bar.
                    .mask { Rectangle().ignoresSafeArea(edges: .vertical) }
                    NavigationStack { feedPage }
                }
                .overlay(alignment: .topLeading) {
                    BookSpine(palette: palette)
                        .frame(width: 12)
                        .offset(x: foldOffset - 6)
                        .ignoresSafeArea()
                }
            } else {
                NavigationSplitView(preferredCompactColumn: $compactColumn) {
                    placeContext
                        .navigationSplitViewColumnWidth(min: 270, ideal: 310, max: 340)
                } detail: {
                    feedPage
                }
                .navigationSplitViewStyle(.balanced)
            }
        }
        .background { foldReader }
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
                    },
                    onReset: {
                        finishedInterestSetup = false
                        activeInterests = []
                        search.reprioritize(for: [])
                    }
                )
                .modelContainer(container)
            case .failure: ContentUnavailableView("Profile unavailable", systemImage: "person.crop.circle")
            }
        }
        .task {
            syncRailCamera()
            await locate(initial: true)
            onFirstLoad(search.status == .results)
        }
        .onChange(of: search.results) {
            camera = .automatic
            syncRailCamera()
        }
        .onChange(of: selection) {
            syncRailCamera()
        }
    }

    private var feedPage: some View {
        Group {
            if showMap, search.status == .results {
                placesMap
                    .mapBlurReveal(palette: palette, trigger: showMap)
                    .safeAreaInset(edge: .bottom) {
                        if let place = selectedLive {
                            FrostedGlassCard(
                                palette: palette,
                                seedKey: place.id,
                                salt: 17,
                                rippleTrigger: mapCardRipple,
                                tapToRipple: true
                            ) {
                                livePlaceContent(place, featured: true)
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
                Button("Profile", systemImage: "person.crop.circle") { profileSheet = .profile }
            }
        }
    }

    @ViewBuilder
    private var foldReader: some View {
        #if compiler(>=6.4.2)
        if #available(iOS 27.1, *) {
            GeometryReader { proxy in
                // A flat inner display still reports the fold as an inactive division region.
                let fold = proxy.reservedRegions(kind: .division, options: [.includeInactive]).first?.frame.midX
                // Ignore a fold outside the middle of this window, such as when Salio shares the screen.
                let offset = fold.flatMap { (proxy.size.width * 0.3...proxy.size.width * 0.7).contains($0) ? $0 : nil }
                Color.clear.onChange(of: offset, initial: true) { _, offset in foldOffset = offset }
            }
        }
        #endif
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
                        seedKey: "onboarding",
                        salt: 4219,
                        tapToRipple: true
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
            .frame(maxWidth: horizontalSizeClass == .regular ? (compactFeedWidth ?? 382) : .infinity)
            .frame(maxWidth: .infinity)
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            if horizontalSizeClass == .compact, width > 0 {
                compactFeedWidth = width
            }
        }
        .background(palette.ground.ignoresSafeArea())
    }

    private var placesMap: some View {
        Map(position: $camera) {
            ForEach(Array(search.results.enumerated()), id: \.element.id) { index, place in
                let selected = selection == .live(place.id)
                Annotation(place.name, coordinate: place.coordinate) {
                    Button {
                        selection = .live(place.id)
                        mapCardRipple += 1
                    } label: {
                        mapPin(number: index + 1, selected: selected, size: 30)
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
                    AsciiLoader(
                        palette: palette,
                        label: "Finding your location",
                        words: ["Getting our bearings…", "Consulting the compass…", "Squinting at maps…", "Sniffing the wind…"]
                    )
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Search places or turn on location to see what’s nearby.")
                            .font(.subheadline)
                            .foregroundStyle(palette.muted)
                        // By now Salio has already asked for location, so only Settings can turn it on.
                        if didLocate, center == nil, let settings = URL(string: UIApplication.openSettingsURLString) {
                            Button("Turn on location") { openURL(settings) }
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(palette.onCTA)
                                .padding(.horizontal, 16)
                                .frame(minHeight: 44)
                                .background(palette.ink, in: Capsule())
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("turn-on-location")
                        }
                    }
                }
            }
        case .searching:
            statusCard {
                AsciiLoader(
                    palette: palette,
                    label: "Finding places",
                    words: ["Rummaging…", "Moseying…", "Sniffing around…", "Scouting…", "Meandering…", "Foraging…", "Pondering…", "Gallivanting…"]
                )
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
        let leaveBy = entry.leaveBy.formatted(date: .omitted, time: .shortened)
        return Button {
            selection = .sample(entry.id)
        } label: {
            HStack(spacing: 12) {
                IndexMarker(symbol: "clock", selected: selected, palette: palette)
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.name)
                        .font(.headline)
                        .foregroundStyle(palette.ink)
                    Text("\(entry.category) · \(entry.walkMinutes) min walk")
                        .font(.subheadline)
                        .foregroundStyle(palette.muted)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(leaveBy)
                        .font(.body.weight(.semibold).monospacedDigit())
                        .foregroundStyle(palette.leaveBy)
                    Text("Leave by")
                        .font(.caption2.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(palette.muted)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Leave by \(leaveBy)")
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func featuredLiveRow(_ place: LivePlace) -> some View {
        let selected = selection == .live(place.id)
        return Button {
            selection = .live(place.id)
            featuredCardRipple += 1
        } label: {
            FrostedGlassCard(
                palette: palette,
                seedKey: place.id,
                salt: 7,
                rippleTrigger: featuredCardRipple
            ) {
                livePlaceContent(place, featured: true)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(place.id)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func liveRow(_ place: LivePlace) -> some View {
        let selected = selection == .live(place.id)
        return Button {
            selection = .live(place.id)
        } label: {
            livePlaceContent(place, featured: false)
                .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(place.id)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// The feed number is the map pin number, so a row and its pin share one label.
    private func indexNumber(of place: LivePlace) -> Int {
        (search.results.firstIndex { $0.id == place.id } ?? 0) + 1
    }

    /// A marker, then the name joined by dots to its distance, like an atlas index entry.
    private func livePlaceContent(_ place: LivePlace, featured: Bool) -> some View {
        let reason = search.matchReason(for: place, interests: activeInterests)
        let summary = place.summary
        return HStack(alignment: .firstTextBaseline, spacing: 12) {
            IndexMarker(number: indexNumber(of: place), selected: selection == .live(place.id), palette: palette)
            VStack(alignment: .leading, spacing: featured ? 5 : 4) {
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text(place.name)
                        .font(featured ? .title3.weight(.bold) : .headline)
                        .foregroundStyle(palette.ink)
                        .layoutPriority(1)
                    if let center {
                        DotLeader(color: palette.border)
                        distanceText(place.distance(from: center))
                            .font(.subheadline.weight(.medium).monospacedDigit())
                            .foregroundStyle(palette.ink)
                            .layoutPriority(1)
                    } else {
                        Spacer(minLength: 0)
                    }
                }
                if !summary.isEmpty || reason != nil {
                    HStack(spacing: 4) {
                        if !summary.isEmpty {
                            Text(summary)
                                .foregroundStyle(palette.muted)
                                .lineLimit(1)
                        }
                        if let reason {
                            if !summary.isEmpty {
                                Text("·")
                                    .foregroundStyle(palette.muted)
                                    .accessibilityHidden(true)
                            }
                            Text(reason)
                                .fontWeight(.semibold)
                                .foregroundStyle(palette.signal)
                                .layoutPriority(1)
                        }
                    }
                    .font(.subheadline)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func distanceText(_ meters: CLLocationDistance) -> Text {
        Text(Measurement(value: meters, unit: UnitLength.meters).formatted(.measurement(width: .abbreviated, usage: .road)))
    }

    private var placeContext: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                railMap
                    .mapBlurReveal(palette: palette, trigger: railMapRevealKey)
                    .frame(height: foldOffset == nil ? 180 : 240)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(palette.border, lineWidth: 1)
                    )

                if selectedSample != nil || selectedLive != nil {
                    Group {
                        if let sample = selectedSample {
                            FrostedGlassCard(
                                palette: palette,
                                seedKey: sample.id,
                                salt: 29,
                                tapToRipple: true
                            ) {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(sample.name)
                                        .font(.headline)
                                        .foregroundStyle(palette.ink)
                                    Text("\(sample.category) · \(sample.walkMinutes) min walk")
                                        .font(.subheadline)
                                        .foregroundStyle(palette.muted)

                                    VStack(spacing: 8) {
                                        contextMetricRow("Walk", value: "\(sample.walkMinutes) min")
                                        Divider().overlay(palette.border)
                                        contextMetricRow(
                                            "Closes",
                                            value: sample.closesAt.formatted(date: .omitted, time: .shortened)
                                        )
                                        Divider().overlay(palette.border)
                                        contextMetricRow(
                                            "Leave by",
                                            value: sample.leaveBy.formatted(date: .omitted, time: .shortened),
                                            valueColor: palette.leaveBy
                                        )
                                    }
                                    .padding(.top, 2)

                                    Text("Your leave-by time includes the walk and an hour at the venue before it closes.")
                                        .font(.caption)
                                        .foregroundStyle(palette.muted)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        } else if let live = selectedLive {
                            FrostedGlassCard(
                                palette: palette,
                                seedKey: live.id,
                                salt: 37,
                                tapToRipple: true
                            ) {
                                VStack(alignment: .leading, spacing: 10) {
                                    if let reason = search.matchReason(for: live, interests: activeInterests) {
                                        Text(reason)
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(palette.signal)
                                    }
                                    Text(live.name)
                                        .font(.headline)
                                        .foregroundStyle(palette.ink)
                                    if !live.address.isEmpty {
                                        Text(live.address)
                                            .font(.subheadline)
                                            .foregroundStyle(palette.muted)
                                    }
                                    Button("Open in Maps") {
                                        openInMaps(name: live.name, coordinate: live.coordinate)
                                    }
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(palette.onCTA)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(palette.ink, in: Capsule())
                                    .buttonStyle(.plain)
                                    .padding(.top, 2)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }

                alsoNearby
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
        .background(palette.ground.ignoresSafeArea())
        .navigationTitle(selectedSample == nil ? "Place details" : "Timing")
    }

    /// Up to three other places closest to the selected one, so the left page answers "what else is near?".
    @ViewBuilder
    private var alsoNearby: some View {
        let anchor = selectedLive?.coordinate ?? selectedSample?.coordinate
        let others = search.results.filter { $0.id != selectedLive?.id }
        if let anchor, !others.isEmpty {
            let from = CLLocation(latitude: anchor.latitude, longitude: anchor.longitude)
            let nearest = others
                .map { ($0, from.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude))) }
                .sorted { $0.1 < $1.1 }
                .prefix(3)
            VStack(alignment: .leading, spacing: 8) {
                Text("Also nearby")
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(palette.muted)
                    .padding(.horizontal, 4)
                VStack(spacing: 0) {
                    ForEach(Array(nearest), id: \.0.id) { place, meters in
                        Button {
                            selection = .live(place.id)
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(place.name)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(palette.ink)
                                    .lineLimit(1)
                                    .layoutPriority(1)
                                DotLeader(color: palette.border)
                                distanceText(meters)
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(palette.muted)
                                    .layoutPriority(1)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("nearby-\(place.id)")
                    }
                }
                .background(palette.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(palette.border, lineWidth: 1)
                )
            }
        }
    }

    private var railMap: some View {
        Map(position: $railCamera) {
            if let live = selectedLive {
                ForEach(Array(search.results.enumerated()), id: \.element.id) { index, place in
                    let isSelected = place.id == live.id
                    Annotation(place.name, coordinate: place.coordinate) {
                        Button {
                            selection = .live(place.id)
                        } label: {
                            mapPin(number: index + 1, selected: isSelected, size: isSelected ? 30 : 24)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(place.name)
                        .accessibilityIdentifier("rail-pin-\(place.id)")
                    }
                    .annotationTitles(.hidden)
                }
            } else if let sample = selectedSample {
                Annotation(sample.name, coordinate: sample.coordinate) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.white, palette.signal)
                        .accessibilityHidden(true)
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
    }

    /// The same numbered marker as the feed row, lifted off the map, with a 44pt hit area.
    private func mapPin(number: Int, selected: Bool, size: CGFloat) -> some View {
        IndexMarker(number: number, selected: selected, palette: palette, size: size)
            .shadow(color: .black.opacity(0.22), radius: 2, y: 1)
            .frame(width: 44, height: 44)
    }

    private func contextMetricRow(_ label: String, value: String, valueColor: Color? = nil) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(palette.muted)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(valueColor ?? palette.ink)
        }
    }

    private func syncRailCamera() {
        let target: CLLocationCoordinate2D?
        if let live = selectedLive {
            target = live.coordinate
        } else if let sample = selectedSample {
            target = sample.coordinate
        } else {
            target = search.results.first?.coordinate
        }
        guard let target else {
            railCamera = .automatic
            return
        }
        railCamera = .region(
            MKCoordinateRegion(center: target, latitudinalMeters: 750, longitudinalMeters: 750)
        )
    }

    private func openInMaps(name: String, coordinate: CLLocationCoordinate2D) {
        let item: MKMapItem
        if #available(iOS 26, *) {
            item = MKMapItem(location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude), address: nil)
        } else {
            item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        }
        item.name = name
        item.openInMaps()
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
}
