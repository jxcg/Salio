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
                // Decorative, and VoiceOver reads the label, so it stops growing at large text sizes.
                .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                .padding(.top, 24)
                .padding(.horizontal, 24)

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
                // Padding inside the scroll view, so its scroll bar sits in the margin, not on the cards.
                .padding(.horizontal, 24)
            }
            // A new scroll view per step, so each screen starts at its title.
            .id(step)
            .transition(.opacity)
            .scrollBounceBehavior(.basedOnSize)
            // Scrolled content fades out at both edges instead of being cut off. The fades sit
            // inside the content's own padding, so nothing is faded until it scrolls.
            .mask {
                VStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: 28)
                    Color.black
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: 28)
                }
            }

            actions
                .padding(.horizontal, 24)
        }
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
            // Two columns, or one at accessibility text sizes so names wrap between words. A plain
            // grid, not a lazy one: there are only six cards, and all of them exist for VoiceOver.
            let columns = dynamicTypeSize.isAccessibilitySize ? 1 : 2
            let all = Preferences.kinds
            Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                ForEach(Array(stride(from: 0, to: all.count, by: columns)), id: \.self) { first in
                    GridRow {
                        ForEach(all[first..<min(first + columns, all.count)], id: \.name) { kindButton($0.name, symbol: $0.symbol) }
                    }
                }
            }
        }
    }

    private func kindButton(_ name: String, symbol: String) -> some View {
        let selected = kinds.contains(name)
        return Button {
            if selected { kinds.remove(name) } else { kinds.insert(name) }
        } label: {
            HStack(spacing: 10) {
                // The icon stops growing at large text sizes and sits in a fixed column,
                // so every name starts at the same edge and keeps the width it needs.
                Image(systemName: symbol)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                    .frame(width: 36)
                Text(name)
                    // Still very large, but leaves room for the choices to fit.
                    .dynamicTypeSize(...DynamicTypeSize.accessibility3)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(selected ? palette.onCTA : palette.ink)
            // Fills the row's height, so the two cards in a row always match.
            .frame(maxWidth: .infinity, minHeight: 52, maxHeight: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(selected ? palette.ink : palette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(palette.border, lineWidth: selected ? 0 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("onboarding-kind-\(name)")
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
        // Keeps the buttons from crowding out the choices at the largest text sizes,
        // and leaves a gap so scrolled content never runs into them.
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .padding(.top, 12)
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
