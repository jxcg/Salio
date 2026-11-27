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
    /// The character the newest step dot is filling in through, or nil once it's full.
    @State private var filling: Character?

    private var palette: SalioPalette {
        appearance.palette(for: colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ASCII step marker, such as `● ○ ○`. The newest step fills in through `· : +` first.
            Text((0..<3).map { $0 < step ? "●" : $0 == step ? filling.map(String.init) ?? "●" : "○" }.joined(separator: " "))
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(palette.signal)
                .accessibilityLabel("Step \(step + 1) of 3")
                // Decorative, and VoiceOver reads the label, so it stops growing at large text sizes.
                .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                .padding(.top, 24)
                .padding(.horizontal, 24)
                .task(id: step) {
                    guard step > 0, !reduceMotion else { return }
                    for character in "·:+" {
                        filling = character
                        try? await Task.sleep(for: .milliseconds(70))
                    }
                    filling = nil
                }

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
            .transition(Self.stepChange)
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
                .id(step)
                .transition(Self.stepChange)
        }
        .padding(.bottom, 12)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // The opening's own colour, so it fades onto onboarding and bursts off it seamlessly.
        .background(Color("LaunchBackground").ignoresSafeArea())
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: step)
    }

    /// The old screen fades out before the new one fades in, so the two never overlap.
    private static let stepChange = AnyTransition.asymmetric(
        insertion: .opacity.animation(.easeOut(duration: 0.18).delay(0.1)),
        removal: .opacity.animation(.easeIn(duration: 0.1))
    )

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 20) {
            heading(
                "Somewhere worth going, nearby.",
                "Salio shows places within walking distance that suit what you’re after. Everything stays on this device."
            )
            art(AsciiRadar(palette: palette))
        }
    }

    private var kindPicker: some View {
        VStack(alignment: .leading, spacing: 20) {
            heading("What are you looking for?", "Nearby only shows these. Choose as many as you like, or skip to see everything.")
            // An atlas index, like the feed: every kind is a numbered row in one card.
            VStack(spacing: 0) {
                ForEach(Array(Preferences.kinds.enumerated()), id: \.element.name) { index, kind in
                    kindRow(index + 1, kind.name, symbol: kind.symbol)
                }
            }
            .padding(.vertical, 4)
            .background(palette.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(palette.border, lineWidth: 1))
        }
    }

    private func kindRow(_ number: Int, _ name: String, symbol: String) -> some View {
        let selected = kinds.contains(name)
        return Button {
            if selected { kinds.remove(name) } else { kinds.insert(name) }
        } label: {
            HStack(spacing: 12) {
                IndexMarker(number: number, selected: selected, palette: palette)
                Image(systemName: symbol)
                    .foregroundStyle(selected ? palette.signal : palette.muted)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                    // A small hop when it's chosen.
                    .symbolEffect(.bounce, options: .speed(1.4), value: selected)
                    // A fixed column, so every name starts at the same edge.
                    .frame(width: 32)
                Text(name)
                    .font(.headline)
                    .foregroundStyle(palette.ink)
                    // Still very large, but keeps "Restaurants" whole on one line.
                    .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                    .layoutPriority(1)
                // Large names need the leader's room to wrap between words.
                if dynamicTypeSize.isAccessibilitySize {
                    Spacer(minLength: 0)
                } else {
                    DotLeader(color: palette.border)
                }
                // An ASCII tick box, so choosing reads like filling in a list.
                Text(selected ? "[×]" : "[ ]")
                    .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                    .foregroundStyle(selected ? palette.signal : palette.muted)
                    .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                    .fixedSize()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.98))
        .sensoryFeedback(.selection, trigger: selected)
        .accessibilityLabel(name)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("onboarding-kind-\(name)")
    }

    private var location: some View {
        VStack(alignment: .leading, spacing: 20) {
            heading(
                "Find what’s around you",
                "Salio uses your location to find places within walking distance. It stays on this device and is never sent anywhere."
            )
            art(AsciiRoute(palette: palette))
        }
    }

    /// Fills the empty space below the words, so it's left out when large text needs that space.
    @ViewBuilder
    private func art(_ content: some View) -> some View {
        if !dynamicTypeSize.isAccessibilitySize {
            content
                .frame(height: 252)
                .padding(.top, 12)
        }
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
            .buttonStyle(PressStyle(scale: 0.97))
            .accessibilityIdentifier(id)
    }

    private func secondary(_ title: String, id: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(palette.ink)
            .frame(maxWidth: .infinity, minHeight: 44)
            .buttonStyle(PressStyle(scale: 0.94))
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
        .buttonStyle(PressStyle(scale: 0.92))
        .sensoryFeedback(.selection, trigger: selected)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Shrinks a button a little while it's held and springs back, slightly past full size, when
/// it's let go, so taps feel physical. Smaller controls take a deeper `scale`, so they read as
/// pressed too. Under Reduce Motion the button dims instead of moving.
struct PressStyle: ButtonStyle {
    var scale: CGFloat = 0.96

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        // The spring only moves the size and dimming here, never the button's own colours or layout.
        configuration.label
            .animation(pressed ? .easeOut(duration: 0.1) : .spring(response: 0.3, dampingFraction: 0.55)) { content in
                content
                    .scaleEffect(pressed && !reduceMotion ? scale : 1)
                    .opacity(pressed && reduceMotion ? 0.6 : 1)
            }
    }
}
