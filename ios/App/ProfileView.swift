import MapKit
import SwiftData
import SwiftUI

@Model
final class Preferences {
    var interests: [String] = []
    var budget: String?
    var transport: [String] = []

    init() {}

    /// The kinds of place someone can look for, in display order. Nearby only searches the chosen kinds;
    /// choosing none shows every kind.
    static let kinds: [(name: String, symbol: String, categories: [MKPointOfInterestCategory])] = [
        ("Restaurants", "fork.knife", [.restaurant, .foodMarket]),
        ("Cafés and bakeries", "cup.and.saucer", [.cafe, .bakery]),
        ("Bars and nightlife", "wineglass", [.nightlife, .brewery]),
        ("Culture", "building.columns", [.museum, .theater, .musicVenue, .landmark]),
        ("Film", "film", [.movieTheater]),
        ("Outdoors", "leaf", [.park, .beach, .zoo, .aquarium, .amusementPark]),
    ]
    static let kindNames = kinds.map(\.name)

    /// Saved names as current kinds, in display order. Interests saved before kinds existed map onto them.
    static func kinds(from saved: [String]) -> [String] {
        let legacy = ["Food": ["Restaurants", "Cafés and bakeries"], "Art": ["Culture"]]
        let names = Set(saved.flatMap { legacy[$0] ?? [$0] })
        return kindNames.filter(names.contains)
    }

    /// What Nearby asks MapKit for; empty means every kind.
    static func categories(for kinds: [String]) -> [MKPointOfInterestCategory] {
        Self.kinds.filter { kinds.contains($0.name) }.flatMap(\.categories)
    }
}

struct ProfileView: View {
    let onSave: ([String]) -> Void
    let onReset: () -> Void
    let onSetUpAgain: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @AppStorage(SalioAppearance.storageKey) private var appearance: SalioAppearance = .mistGlass
    @AppStorage(SalioOpening.Style.storageKey) private var openingStyle: SalioOpening.Style = .tear
    @AppStorage(OnboardingView.finishedKey) private var finishedOnboarding = false
    @Query private var saved: [Preferences]
    @State private var interests: Set<String> = []
    @State private var budget: String?
    @State private var transport: Set<String> = []
    @State private var confirmingDiscard = false
    @State private var confirmingReset = false
    @State private var showingError = false

    private var palette: SalioPalette {
        appearance.palette(for: colorScheme)
    }

    private var hasChanges: Bool {
        interests != Set(Preferences.kinds(from: saved.first?.interests ?? []))
            || budget != saved.first?.budget
            || transport != Set(saved.first?.transport ?? [])
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    choices(Preferences.kindNames, selection: $interests)
                } header: {
                    Text("What you’re looking for")
                } footer: {
                    Text("Saved on this device. Nearby only shows these; leave them all off to see everything.")
                }
                .listRowBackground(palette.card)

                Picker("Budget", selection: $budget) {
                    Text("Not set").tag(nil as String?)
                    ForEach(["£", "££", "£££"], id: \.self) { level in
                        Text(level).tag(Optional(level))
                    }
                }
                .accessibilityValue(budget ?? "Not set")
                .accessibilityIdentifier("profile-budget")
                .listRowBackground(palette.card)

                Section("Getting around") {
                    choices(["Walking", "Public transport", "Driving"], selection: $transport)
                }
                .listRowBackground(palette.card)

                Section("Appearance") {
                    Picker("Theme", selection: $appearance) {
                        ForEach(SalioAppearance.allCases) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .accessibilityValue(appearance.displayName)
                    .accessibilityIdentifier("profile-theme")
                    Picker("Opening", selection: $openingStyle) {
                        ForEach(SalioOpening.Style.allCases) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .accessibilityValue(openingStyle.displayName)
                    .accessibilityIdentifier("profile-opening")
                }
                .listRowBackground(palette.card)

                Section {
                    Button("Set up Salio again") {
                        finishedOnboarding = false
                        onSetUpAgain()
                    }
                        .accessibilityIdentifier("profile-set-up-again")
                    if !saved.isEmpty {
                        Button("Reset preferences", role: .destructive) { confirmingReset = true }
                    }
                }
                .listRowBackground(palette.card)
            }
            .scrollContentBackground(.hidden)
            .background(palette.ground)
            .tint(palette.signal)
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if hasChanges { confirmingDiscard = true } else { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(!hasChanges) }
            }
            .onAppear {
                guard let preferences = saved.first else { return }
                interests = Set(Preferences.kinds(from: preferences.interests))
                budget = preferences.budget
                transport = Set(preferences.transport)
            }
            .alert("Discard changes?", isPresented: $confirmingDiscard) {
                Button("Keep editing", role: .cancel) {}
                Button("Discard", role: .destructive) { dismiss() }
            }
            .alert("Reset preferences?", isPresented: $confirmingReset) {
                Button("Cancel", role: .cancel) {}
                Button("Reset", role: .destructive, action: reset)
            } message: {
                Text("This clears what you’re looking for, your budget, and travel preferences.")
            }
            .alert("Couldn’t update preferences", isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            }
        }
        .interactiveDismissDisabled(hasChanges)
    }

    private func choices(_ options: [String], selection: Binding<Set<String>>) -> some View {
        ForEach(options, id: \.self) { option in
            Toggle(option, isOn: Binding {
                selection.wrappedValue.contains(option)
            } set: { enabled in
                if enabled {
                    selection.wrappedValue.insert(option)
                } else {
                    selection.wrappedValue.remove(option)
                }
            })
        }
    }

    private func save() {
        let preferences = saved.first ?? Preferences()
        if saved.isEmpty { context.insert(preferences) }
        preferences.interests = Preferences.kindNames.filter(interests.contains)
        preferences.budget = budget
        preferences.transport = transport.sorted()
        if commit() {
            onSave(preferences.interests)
            dismiss()
        }
    }

    private func reset() {
        for preferences in saved { context.delete(preferences) }
        if commit() {
            interests = []
            budget = nil
            transport = []
            onReset()
        }
    }

    private func commit() -> Bool {
        do {
            try context.save()
            return true
        } catch {
            context.rollback()
            showingError = true
            return false
        }
    }
}
