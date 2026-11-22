import SwiftUI

@main
struct SalioApp: App {
    var body: some Scene {
        WindowGroup { FeedView() }
    }
}

private struct FeedEntry: Decodable, Identifiable {
    let id: String
    let name: String
    let category: String
    let walkMinutes: Int
    let closesAt: Date
    let leaveBy: Date
}

private struct FeedView: View {
    @State private var entries: [FeedEntry] = []
    @State private var loading = true
    @State private var failed = false
    @State private var selectedID: FeedEntry.ID?
    @State private var compactColumn: NavigationSplitViewColumn = .detail

    private var selectedPlace: FeedEntry? {
        entries.first { $0.id == selectedID } ?? entries.first
    }

    var body: some View {
        NavigationSplitView(preferredCompactColumn: $compactColumn) {
            placeContext
        } detail: {
            List {
                if !entries.isEmpty {
                    Section("Sample places") {
                        ForEach(entries) { entry in
                            placeRow(entry)
                        }
                    }
                }
            }
            .navigationTitle("Nearby")
            .navigationBarBackButtonHidden()
            .overlay {
                if loading {
                    ProgressView("Loading nearby places")
                } else if failed {
                    ContentUnavailableView("Can’t load places", systemImage: "wifi.slash")
                } else if entries.isEmpty {
                    ContentUnavailableView("Nothing nearby", systemImage: "mappin.slash")
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .task { await load() }
    }

    private func placeRow(_ entry: FeedEntry) -> some View {
        let selected = selectedPlace?.id == entry.id
        return Button {
            selectedID = entry.id
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.name).font(.headline)
                    Text("\(entry.category) · \(entry.walkMinutes) min walk")
                        .foregroundStyle(.secondary)
                    Label {
                        Text("Leave by \(entry.leaveBy.formatted(date: .omitted, time: .shortened))")
                    } icon: {
                        Image(systemName: "clock")
                    }
                    .font(.subheadline.weight(.medium))
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
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var placeContext: some View {
        List {
            if let place = selectedPlace {
                Section {
                    Text(place.name).font(.headline)
                    LabeledContent("Walk", value: "\(place.walkMinutes) min")
                    LabeledContent("Closes", value: place.closesAt.formatted(date: .omitted, time: .shortened))
                } footer: {
                    Text("Your leave-by time includes the walk and an hour at the venue before it closes.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Timing")
    }

    private func load() async {
        defer { loading = false }
        do {
            guard let value = ProcessInfo.processInfo.environment["SALIO_API_URL"],
                  let baseURL = URL(string: value) else { throw URLError(.badURL) }
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
            failed = true
        }
    }
}
