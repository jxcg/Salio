import SwiftData
import SwiftUI

/// Salio's first run: a welcome, the kinds of place someone is looking for, and why Salio needs their
/// location. Every step can be skipped. It saves the kinds to the same on-device `Preferences` that
/// Profile edits, and only asks iOS for location after the last step explains why.
struct OnboardingView: View {
    static var finishedKey: String { SalioTestStore.scopedKey("finishedOnboarding") }

    /// Where the kinds are saved; nil when the profile store couldn't open, so nothing is saved.
    let container: ModelContainer?
    /// Called once, with whether the user chose to let Salio use their location now.
    let onFinish: (_ allowsLocation: Bool) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .subheadline) private var iconWidth = 22.0
    @AppStorage(SalioAppearance.storageKey) private var appearance: SalioAppearance = .mistGlass
    @State private var step = 0
    @State private var kinds: Set<String> = []

    private var palette: SalioPalette {
        appearance.palette(for: colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ASCII step marker, such as `● ○ ○`.
            Text((0..<3).map { $0 <= step ? "●" : "○" }.joined(separator: " "))
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(palette.signal)
                .accessibilityLabel("Step \(step + 1) of 3")
                .padding(.top, 24)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch step {
                    case 0: welcome
                    case 1: kindPicker
                    default: location
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 28)
                .id(step)
                .transition(.opacity)
            }
            .scrollBounceBehavior(.basedOnSize)

            actions
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // The opening's own colour, so it fades onto onboarding and bursts off it seamlessly.
        .background(Color("LaunchBackground").ignoresSafeArea())
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: step)
    }

    private var welcome: some View {
        heading(
            "Somewhere worth going, nearby.",
            "Salio shows places within walking distance that suit what you’re after. Everything stays on this device."
        )
    }

    private var kindPicker: some View {
        VStack(alignment: .leading, spacing: 20) {
            heading("What are you looking for?", "Nearby only shows these. Choose as many as you like, or skip to see everything.")
            // One column at accessibility text sizes, so names wrap between words, not inside them.
            LazyVGrid(columns: dynamicTypeSize.isAccessibilitySize
                      ? [GridItem(.flexible())]
                      : [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                ForEach(Preferences.kinds, id: \.name) { kind in
                    let selected = kinds.contains(kind.name)
                    Button {
                        if selected { kinds.remove(kind.name) } else { kinds.insert(kind.name) }
                    } label: {
                        // A fixed-width icon column keeps every name starting at the same edge; at
                        // accessibility sizes the icon sits above the name so long names keep the width.
                        let layout = dynamicTypeSize.isAccessibilitySize
                            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                            : AnyLayout(HStackLayout(spacing: 10))
                        layout {
                            Image(systemName: kind.symbol).frame(width: iconWidth)
                            Text(kind.name)
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(selected ? palette.onCTA : palette.ink)
                        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                        .padding(.horizontal, 14)
                        .background(selected ? palette.ink : palette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(palette.border, lineWidth: selected ? 0 : 1)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .accessibilityIdentifier("onboarding-kind-\(kind.name)")
                }
            }
        }
    }

    private var location: some View {
        heading(
            "Find what’s around you",
            "Salio uses your location to find places within walking distance. It stays on this device and is never sent anywhere."
        )
    }

    private func heading(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(palette.ink)
                .accessibilityAddTraits(.isHeader)
            Text(detail)
                .font(.body)
                .foregroundStyle(palette.muted)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var actions: some View {
        VStack(spacing: 8) {
            switch step {
            case 0:
                primary("Get started", id: "onboarding-start") { step = 1 }
                secondary("Skip for now", id: "onboarding-skip") { onFinish(false) }
            case 1:
                primary(kinds.isEmpty ? "Show me everything" : "Continue", id: "onboarding-continue") {
                    save()
                    step = 2
                }
                secondary("Skip for now", id: "onboarding-skip") { step = 2 }
            default:
                primary("Use my location", id: "onboarding-allow-location") { onFinish(true) }
                secondary("Not now", id: "onboarding-skip") { onFinish(false) }
            }
        }
    }

    private func primary(_ title: String, id: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.headline)
            .foregroundStyle(palette.onCTA)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(palette.ink, in: Capsule())
            .buttonStyle(.plain)
            .accessibilityIdentifier(id)
    }

    private func secondary(_ title: String, id: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(palette.ink)
            .frame(maxWidth: .infinity, minHeight: 44)
            .buttonStyle(.plain)
            .accessibilityIdentifier(id)
    }

    private func save() {
        guard let context = container?.mainContext else { return }
        let preferences = (try? context.fetch(FetchDescriptor<Preferences>()).first) ?? {
            let new = Preferences()
            context.insert(new)
            return new
        }()
        preferences.interests = Preferences.kindNames.filter(kinds.contains)
        try? context.save()
    }
}

/// A small capsule that turns a kind of place on or off in the feed.
struct KindChip: View {
    let title: String
    let symbol: String?
    let selected: Bool
    let palette: SalioPalette
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol).imageScale(.small) }
                Text(title)
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(selected ? palette.onCTA : palette.ink)
            .padding(.horizontal, 12)
            .frame(minHeight: 36)
            .background(selected ? palette.ink : palette.card, in: Capsule())
            .overlay(Capsule().strokeBorder(palette.border, lineWidth: selected ? 0 : 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
