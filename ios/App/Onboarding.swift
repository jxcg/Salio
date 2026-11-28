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
    private var large: Bool { dynamicTypeSize.isAccessibilitySize }
    /// Kind rows stack the name under its controls a step before accessibility sizes, as soon as
    /// names start to wrap beside them.
    private var stacked: Bool { dynamicTypeSize >= .xxxLarge }
    @ScaledMetric(relativeTo: .headline) private var markerSize = 28.0
    /// Scrolled text fades out over at least one line of itself, so a line never straddles the edge.
    @ScaledMetric(relativeTo: .body) private var scaledFade = 32.0
    private var fade: CGFloat { min(scaledFade, 64) }
    /// The scroll area's height and the current screen's words, so the grid can fill what's left.
    @State private var viewport: CGFloat = 0
    @State private var wordsHeight: CGFloat = 0
    /// Whether a finger is on the grid, and where it has drawn, so the welcome radar can make way for it.
    @State private var drawing = false
    @State private var drawn: [CGPoint] = []
    /// Whether there's content scrolled past the top or bottom edge; only then does that edge fade.
    @State private var hidden: (above: Bool, below: Bool) = (false, false)
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
            HStack(alignment: .firstTextBaseline) {
            // ASCII step marker, such as `● ○ ○`. The newest step fills in through `· : +` first.
            Text((0..<3).map { $0 < step ? "●" : $0 == step ? filling.map(String.init) ?? "●" : "○" }.joined(separator: " "))
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(palette.signal)
                .accessibilityLabel("Step \(step + 1) of 3")
                // Decorative, and VoiceOver reads the label, so it stops growing at large text sizes.
                .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                .task(id: step) {
                    guard step > 0, !reduceMotion else { return }
                    for character in "·:+" {
                        filling = character
                        try? await Task.sleep(for: .milliseconds(70))
                    }
                    filling = nil
                }
                Spacer(minLength: 16)
                // At accessibility sizes the way out sits up here, so only the main button is pinned
                // below and the choices keep most of the screen.
                if large {
                    skip
                        .fixedSize()
                        // Secondary, so it never competes with the title.
                        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                }
            }
            .padding(.top, 24)
            .padding(.horizontal, 24)
            .padding(.bottom, 12)

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
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { viewport = $0 }
            .onScrollGeometryChange(for: [Bool].self) { geometry in
                let top = geometry.contentOffset.y + geometry.contentInsets.top
                return [top > 1, top + geometry.containerSize.height < geometry.contentSize.height - 1]
            } action: { _, edges in
                hidden = (edges[0], edges[1])
            }
            // Scrolled content fades out at both edges instead of being cut off.
            .mask {
                VStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: hidden.above ? fade : 0)
                    Color.black
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: hidden.below ? fade : 0)
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
            art(AsciiRadar(palette: palette, holding: drawing, touches: drawn))
        }
    }

    private var kindPicker: some View {
        VStack(alignment: .leading, spacing: 20) {
            heading(
                "What are you looking for?",
                // Shorter at accessibility sizes, so the first choices show without scrolling.
                large ? "Nearby only shows these. Choose any." : "Nearby only shows these. Choose as many as you like, or skip to see everything."
            )
            // An atlas index, like the feed: every kind is a numbered row in one card.
            VStack(spacing: 0) {
                ForEach(Array(Preferences.kinds.enumerated()), id: \.element.name) { index, kind in
                    // Two-line rows at accessibility sizes need a rule between them to read as separate.
                    if stacked, index > 0 {
                        Rectangle().fill(palette.border).frame(height: 1).padding(.horizontal, 14)
                    }
                    kindRow(index + 1, kind.name, symbol: kind.symbol)
                }
            }
            .background(palette.card)
            // Clipped, so the first and last rows' wash follows the card's corners.
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(palette.border, lineWidth: 1))
        }
    }

    private func kindRow(_ number: Int, _ name: String, symbol: String) -> some View {
        let selected = kinds.contains(name)
        return Button {
            if selected { kinds.remove(name) } else { kinds.insert(name) }
        } label: {
            // The marker and tick box grow with the text, so the row's state stays as easy to read as its name.
            let marker = IndexMarker(number: number, selected: selected, palette: palette, size: min(markerSize, 40))
            let icon = Image(systemName: symbol)
                .foregroundStyle(selected ? palette.signal : palette.muted)
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                // A small hop when it's chosen.
                .symbolEffect(.bounce, options: .speed(1.4), value: selected)
                // A fixed column, so every name starts at the same edge.
                .frame(width: 32)
            // An ASCII tick box, so choosing reads like filling in a list.
            let tick = Text(selected ? "[×]" : "[ ]")
                .font(.system(.headline, design: .monospaced).weight(.semibold))
                .foregroundStyle(selected ? palette.signal : palette.muted)
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                .fixedSize()
            let title = Text(name)
                .font(.headline)
                .foregroundStyle(palette.ink)
                .dynamicTypeSize(...DynamicTypeSize.accessibility3)
            Group {
            if stacked {
                // Large names get the row's whole width on their own line, under the marker and tick,
                // so they wrap between words and never crowd the controls.
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        marker
                        icon
                        Spacer(minLength: 0)
                        tick
                    }
                    title.frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                HStack(spacing: 12) {
                    marker
                    icon
                    title.layoutPriority(1)
                    DotLeader(color: palette.border)
                    tick
                }
            }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            // A faint wash marks chosen rows as a whole, not just by their tick box.
            .background(selected ? palette.signal.opacity(0.08) : .clear)
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

    /// Fills the room left under the words, and can be drawn on with a finger. When large text leaves too
    /// little room for a real grid, it's left out, so the screen never scrolls because of it.
    @ViewBuilder
    private func art(_ content: some View) -> some View {
        // The scroll content's vertical padding, the stack's spacing, and the art's own top gap.
        let room = viewport - 56 - 20 - 12 - wordsHeight
        if room >= 96 {
            content
                .frame(height: min(room, 340))
                .modifier(AsciiTouchTrail(palette: palette) { drawing = $0; drawn = $1 })
                .padding(.top, 12)
        }
    }

    private func heading(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: large ? 6 : 10) {
            Text(title)
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(palette.ink)
                // At the largest sizes the title would take three lines for five words; capped (with the
                // body), the words and the choices come into view sooner.
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                .accessibilityAddTraits(.isHeader)
            Text(detail)
                .font(.body)
                .foregroundStyle(palette.muted)
                // Capped with the title, so the title is never the smaller of the two.
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        }
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { wordsHeight = $0 }
    }

    private var actions: some View {
        VStack(spacing: 8) {
            switch step {
            case 0:
                primary("Get started", id: "onboarding-start") { step = 1 }
            case 1:
                primary(kinds.isEmpty ? "Show me everything" : "Continue", id: "onboarding-continue") {
                    save()
                    step = 2
                }
            default:
                primary("Use my location", id: "onboarding-allow-location") { onFinish(true) }
            }
            if !large { skip }
        }
        // Keeps the buttons from crowding out the choices at the largest text sizes,
        // and leaves a gap so scrolled content never runs into them.
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .padding(.top, 12)
    }

    /// The way past this step without choosing.
    private var skip: some View {
        secondary(step == 2 ? "Not now" : "Skip for now", id: "onboarding-skip") {
            if step == 1 { step = 2 } else { onFinish(false) }
        }
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
