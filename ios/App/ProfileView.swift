import MapKit
import SwiftData
import SwiftUI

@Model
final class Preferences {
    var interests: [String] = []
    var budget: String?
    var transport: [String] = []

    init() {}

    static let categoriesByInterest: [String: [MKPointOfInterestCategory]] = [
        "Art": [.museum, .theater],
        "Film": [.movieTheater],
        "Food": [.cafe, .bakery, .restaurant, .foodMarket],
        "Outdoors": [.park, .beach, .zoo],
    ]

    static func matchingInterest(for category: MKPointOfInterestCategory?, in interests: [String]) -> String? {
        guard let category else { return nil }
        return interests.sorted().first { categoriesByInterest[$0, default: []].contains(category) }
    }
}

struct ProfileView: View {
    let interestsOnly: Bool
    let onSave: ([String]) -> Void
    let onReset: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @AppStorage(SalioAppearance.storageKey) private var appearance: SalioAppearance = .mistGlass
    @AppStorage(SalioOpening.Style.storageKey) private var openingStyle: SalioOpening.Style = .tear
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
        interests != Set(saved.first?.interests ?? [])
            || budget != saved.first?.budget
            || transport != Set(saved.first?.transport ?? [])
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    choices(Preferences.categoriesByInterest.keys.sorted(), selection: $interests)
                } header: {
                    Text("Interests")
                } footer: {
                    Text("Saved on this device. Matching Nearby places appear first.")
                }
                .listRowBackground(palette.card)

                if !interestsOnly {
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

                    if !saved.isEmpty {
                        Section {
                            Button("Reset preferences", role: .destructive) { confirmingReset = true }
                        }
                        .listRowBackground(palette.card)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(palette.ground)
            .tint(palette.signal)
            .navigationTitle(interestsOnly ? "Choose interests" : "Profile")
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
                interests = Set(preferences.interests)
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
                Text("This clears your saved interests, budget, and travel preferences.")
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
        preferences.interests = interests.sorted()
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
