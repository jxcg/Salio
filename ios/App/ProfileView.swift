import SwiftData
import SwiftUI

@Model
final class Preferences {
    var interests: [String] = []
    var budget: String?
    var transport: [String] = []

    init() {}
}

struct ProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var saved: [Preferences]
    @State private var interests: Set<String> = []
    @State private var budget: String?
    @State private var transport: Set<String> = []
    @State private var confirmingDiscard = false
    @State private var confirmingReset = false
    @State private var showingError = false

    private var hasChanges: Bool {
        interests != Set(saved.first?.interests ?? [])
            || budget != saved.first?.budget
            || transport != Set(saved.first?.transport ?? [])
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    choices(["Art", "Film", "Food", "Outdoors"], selection: $interests)
                } header: {
                    Text("Interests")
                } footer: {
                    Text("Saved on this device.")
                }

                Picker("Budget", selection: $budget) {
                    Text("Not set").tag(nil as String?)
                    ForEach(["£", "££", "£££"], id: \.self) { level in
                        Text(level).tag(Optional(level))
                    }
                }
                .accessibilityValue(budget ?? "Not set")
                .accessibilityIdentifier("profile-budget")

                Section("Getting around") {
                    choices(["Walking", "Public transport", "Driving"], selection: $transport)
                }

                if !saved.isEmpty {
                    Section {
                        Button("Reset preferences", role: .destructive) { confirmingReset = true }
                    }
                }
            }
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
        if commit() { dismiss() }
    }

    private func reset() {
        for preferences in saved { context.delete(preferences) }
        if commit() {
            interests = []
            budget = nil
            transport = []
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
