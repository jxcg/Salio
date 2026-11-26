import SwiftUI

enum SalioTestStore {
    static var name: String? {
        #if DEBUG
        ProcessInfo.processInfo.environment["SALIO_PROFILE_TEST_STORE"]
        #else
        nil
        #endif
    }

    static func scopedKey(_ base: String) -> String {
        if let name {
            return "\(base).\(name)"
        }
        return base
    }
}

enum SalioAppearance: String, CaseIterable, Identifiable, Sendable {
    case mistGlass
    case stoneAmber

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mistGlass: "Mist & Glass"
        case .stoneAmber: "Stone & Amber"
        }
    }

    static var storageKey: String {
        SalioTestStore.scopedKey("salioAppearance")
    }

    func palette(for colorScheme: ColorScheme) -> SalioPalette {
        switch (self, colorScheme) {
        case (.mistGlass, .dark):
            SalioPalette(
                ground: Color(hex: 0x0B0C10),
                card: Color(hex: 0x151720),
                soft: Color(hex: 0x1F2230),
                border: Color(hex: 0x2A2E40),
                ink: Color(hex: 0xF4F5F8),
                onCTA: Color(hex: 0x0B0C10),
                muted: Color(hex: 0x9CA2B3),
                signal: Color(hex: 0xB7AEDD),
                leaveBy: Color(hex: 0x4CC38A),
                causticWarm: Color(hex: 0xE89F6E, opacity: 0.16),
                causticCool: Color(hex: 0x9586E0, opacity: 0.14),
                reticlePrimary: Color.white.opacity(0.22),
                reticleSecondary: Color.white.opacity(0.11)
            )
        case (.mistGlass, _):
            SalioPalette(
                ground: Color(hex: 0xF2F3F6),
                card: Color(hex: 0xFCFCFD),
                soft: Color(hex: 0xE6E8EF),
                border: Color(hex: 0xDFE2EA),
                ink: Color(hex: 0x0D0F14),
                onCTA: Color.white,
                muted: Color(hex: 0x5A5F6C),
                signal: Color(hex: 0x6A5BB3),
                leaveBy: Color(hex: 0x1D8150),
                causticWarm: Color(hex: 0xF0A670, opacity: 0.22),
                causticCool: Color(hex: 0x7666C6, opacity: 0.14),
                reticlePrimary: Color(hex: 0x0D0F14, opacity: 0.24),
                reticleSecondary: Color(hex: 0x0D0F14, opacity: 0.12)
            )
        case (.stoneAmber, .dark):
            SalioPalette(
                ground: Color(hex: 0x0E0F0E),
                card: Color(hex: 0x171917),
                soft: Color(hex: 0x222522),
                border: Color(hex: 0x2E322E),
                ink: Color(hex: 0xF3F4F2),
                onCTA: Color(hex: 0x0E0F0E),
                muted: Color(hex: 0xA0A5A0),
                signal: Color(hex: 0xE69B42),
                leaveBy: Color(hex: 0x4CC38A),
                causticWarm: Color(hex: 0xDF9A44, opacity: 0.16),
                causticCool: Color(hex: 0x988AD8, opacity: 0.11),
                reticlePrimary: Color.white.opacity(0.22),
                reticleSecondary: Color.white.opacity(0.11)
            )
        case (.stoneAmber, _):
            SalioPalette(
                ground: Color(hex: 0xEFF0EE),
                card: Color(hex: 0xFAFBFA),
                soft: Color(hex: 0xE4E6E2),
                border: Color(hex: 0xDCDFDA),
                ink: Color(hex: 0x101211),
                onCTA: Color.white,
                muted: Color(hex: 0x5C605D),
                signal: Color(hex: 0xC87316),
                leaveBy: Color(hex: 0x1D8150),
                causticWarm: Color(hex: 0xE8A54C, opacity: 0.22),
                causticCool: Color(hex: 0x8272CC, opacity: 0.11),
                reticlePrimary: Color(hex: 0x101211, opacity: 0.24),
                reticleSecondary: Color(hex: 0x101211, opacity: 0.12)
            )
        }
    }
}

struct SalioPalette: Equatable {
    let ground: Color
    let card: Color
    let soft: Color
    let border: Color
    let ink: Color
    let onCTA: Color
    let muted: Color
    let signal: Color
    let leaveBy: Color
    let causticWarm: Color
    let causticCool: Color
    let reticlePrimary: Color
    let reticleSecondary: Color
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        let red = Double((hex >> 16) & 0xFF) / 255
        let green = Double((hex >> 8) & 0xFF) / 255
        let blue = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }
}

struct RefractedReticleSurface: View {
    let palette: SalioPalette
    let rippleStart: Date?
    /// Tap location in the surface's coordinates; nil ripples from near the center.
    let rippleOrigin: CGPoint?
    var seed: Int = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var isRippling = false

    private static let rippleDuration: TimeInterval = 0.62

    private var allowsRefraction: Bool {
        !reduceMotion && !voiceOver && contrast != .increased
    }

    var body: some View {
        TimelineView(.animation(paused: !(isRippling && allowsRefraction))) { timeline in
            GeometryReader { proxy in
                let size = proxy.size
                let progress = isRippling ? rippleProgress(at: timeline.date) : nil
                let active = allowsRefraction && progress != nil
                let t = progress ?? 0
                let eased = 1 - pow(1 - t, 3)
                let maxRadius = hypot(size.width, size.height) * 0.95
                let origin = rippleOrigin.map {
                    CGPoint(
                        x: min(max($0.x, size.width * 0.08), size.width * 0.92),
                        y: min(max($0.y, size.height * 0.08), size.height * 0.92)
                    )
                } ?? CGPoint(x: size.width * 0.55, y: size.height * 0.48)
                let strength = active ? Float(sin(t * .pi)) : 0

                // Equatable so ripple frames reuse the drawn reticle instead of redrawing it.
                ReticleCanvas(palette: palette, seed: seed, showsReticle: contrast != .increased)
                    .equatable()
                    .layerEffect(
                        ShaderLibrary.frostedRefraction(
                            .float2(origin),
                            .float(Float(eased * maxRadius)),
                            .float(34),
                            .float(strength),
                            .float(2.6)
                        ),
                        maxSampleOffset: CGSize(width: 20, height: 20),
                        isEnabled: active
                    )
            }
        }
        .task(id: rippleStart) {
            guard rippleStart != nil, allowsRefraction else {
                isRippling = false
                return
            }
            isRippling = true
            do {
                try await Task.sleep(for: .milliseconds(650))
                isRippling = false
            } catch {
                // Newer ripple or view dismissal cancels the pending stop cleanly.
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func rippleProgress(at date: Date) -> Double? {
        guard let rippleStart else { return nil }
        let elapsed = date.timeIntervalSince(rippleStart)
        guard elapsed >= 0, elapsed < Self.rippleDuration else { return nil }
        return elapsed / Self.rippleDuration
    }

    static func drawAsciiScatter(
        in context: inout GraphicsContext,
        size: CGSize,
        seed: Int,
        step: CGSize,
        emptyPercent: Int,
        glyphs: [(Int, GraphicsContext.ResolvedText)]
    ) {
        let cols = Int(size.width / step.width) + 1
        let rows = Int(size.height / step.height) + 1
        let halfX = step.width * 0.52
        let halfY = step.height * 0.52

        for row in 0..<rows {
            for col in 0..<cols {
                let h = cellHash(row: row, col: col, seed: seed)
                let bucket = Int(h % 100)
                guard bucket >= emptyPercent else { continue }

                let jitterX = CGFloat(Int((h >> 8) % 9) - 4) * 0.85
                let jitterY = CGFloat(Int((h >> 12) % 9) - 4) * 0.85
                let point = CGPoint(
                    x: CGFloat(col) * step.width + halfX + jitterX,
                    y: CGFloat(row) * step.height + halfY + jitterY
                )

                if let glyph = glyphs.first(where: { bucket < $0.0 })?.1 {
                    context.draw(glyph, at: point, anchor: .center)
                }
            }
        }
    }

    static func seed(for key: String, salt: Int = 0) -> Int {
        key.unicodeScalars.reduce(salt) { $0 &* 31 &+ Int($1.value) }
    }

    fileprivate static func cellHash(row: Int, col: Int, seed: Int) -> UInt64 {
        var h = UInt64(bitPattern: Int64(row &* 73_856_093 ^ col &* 19_349_663 ^ seed &* 83_492_791))
        h ^= h >> 30
        h &*= 0xBF58_476D_1CE4_E5B9
        h ^= h >> 27
        h &*= 0x94D0_49BB_1331_11EB
        return h ^ (h >> 31)
    }
}

private struct ReticleCanvas: View, Equatable {
    let palette: SalioPalette
    let seed: Int
    let showsReticle: Bool

    var body: some View {
        Canvas(rendersAsynchronously: false) { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(palette.card))

            guard showsReticle else { return }

            let warmCenter = CGPoint(x: size.width * 0.80, y: size.height * 0.24)
            let warmRadius = max(size.width, size.height) * 0.68
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .radialGradient(
                    Gradient(colors: [palette.causticWarm, .clear]),
                    center: warmCenter,
                    startRadius: 6,
                    endRadius: warmRadius
                )
            )

            let coolCenter = CGPoint(x: size.width * 0.22, y: size.height * 0.82)
            let coolRadius = max(size.width, size.height) * 0.56
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .radialGradient(
                    Gradient(colors: [palette.causticCool, .clear]),
                    center: coolCenter,
                    startRadius: 6,
                    endRadius: coolRadius
                )
            )

            let glyphs: [(Int, GraphicsContext.ResolvedText)] = [
                (74, context.resolve(Text("·").font(.system(size: 10, weight: .regular, design: .monospaced)).foregroundStyle(palette.reticleSecondary))),
                (87, context.resolve(Text(".").font(.system(size: 9, weight: .regular, design: .monospaced)).foregroundStyle(palette.reticleSecondary))),
                (95, context.resolve(Text("+").font(.system(size: 9, weight: .regular, design: .monospaced)).foregroundStyle(palette.reticlePrimary))),
                (98, context.resolve(Text(":").font(.system(size: 8.5, weight: .regular, design: .monospaced)).foregroundStyle(palette.reticleSecondary))),
                (100, context.resolve(Text("/").font(.system(size: 8.5, weight: .regular, design: .monospaced)).foregroundStyle(palette.reticlePrimary.opacity(0.65)))),
            ]
            RefractedReticleSurface.drawAsciiScatter(
                in: &context,
                size: size,
                seed: seed,
                step: CGSize(width: 19, height: 17),
                emptyPercent: 44,
                glyphs: glyphs
            )
        }
    }
}

struct FrostedGlassCard<Content: View>: View {
    let palette: SalioPalette
    let seed: Int
    var rippleTrigger: Int = 0
    var tapToRipple: Bool = false
    @ViewBuilder let content: () -> Content

    init(
        palette: SalioPalette,
        seedKey: String,
        salt: Int = 0,
        rippleTrigger: Int = 0,
        tapToRipple: Bool = false,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.palette = palette
        self.seed = RefractedReticleSurface.seed(for: seedKey, salt: salt)
        self.rippleTrigger = rippleTrigger
        self.tapToRipple = tapToRipple
        self.content = content
    }

    @State private var rippleStart: Date?
    @State private var rippleOrigin: CGPoint?

    var body: some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RefractedReticleSurface(
                    palette: palette,
                    rippleStart: rippleStart,
                    rippleOrigin: rippleOrigin,
                    seed: seed
                )
            }
            .simultaneousGesture(
                SpatialTapGesture().onEnded { value in
                    rippleOrigin = value.location
                    rippleStart = Date()
                },
                isEnabled: tapToRipple
            )
            .onChange(of: rippleTrigger) {
                rippleOrigin = nil
                rippleStart = Date()
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(palette.border, lineWidth: 1)
            )
    }
}

struct MapBlurRevealModifier<Trigger: Equatable>: ViewModifier {
    let palette: SalioPalette
    let trigger: Trigger

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var revealStart: Date?
    @State private var isRevealing = false

    private let duration: TimeInterval = 0.85

    private var allowsReveal: Bool {
        !reduceMotion && !voiceOver && contrast != .increased
    }

    func body(content: Content) -> some View {
        TimelineView(.animation(paused: !(isRevealing && allowsReveal))) { timeline in
            let progress: Double? = isRevealing ? revealProgress(at: timeline.date) : nil
            let active = allowsReveal && progress != nil
            let t = progress ?? 1
            let ease = 1 - pow(1 - t, 3)
            let blurAmount = active ? (1 - ease) * 12 : 0
            let veilOpacity = active ? (1 - ease) * 0.96 : 0
            let frameSeed = Int(t * 7) * 131 + 19

            content
                .blur(radius: blurAmount)
                .overlay {
                    if veilOpacity > 0.01 {
                        AsciiVeil(palette: palette, seed: frameSeed)
                            .equatable()
                            .opacity(veilOpacity)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
        }
        .task(id: trigger) {
            guard allowsReveal else {
                isRevealing = false
                revealStart = nil
                return
            }
            revealStart = Date()
            isRevealing = true
            do {
                try await Task.sleep(for: .milliseconds(900))
                isRevealing = false
            } catch {
                // Newer map transition cancels the pending reveal stop cleanly.
            }
        }
    }

    private func revealProgress(at date: Date) -> Double? {
        guard let revealStart else { return nil }
        let elapsed = date.timeIntervalSince(revealStart)
        guard elapsed >= 0, elapsed < duration else { return nil }
        return elapsed / duration
    }
}

/// Equatable so reveal frames redraw the veil only when its seed changes.
private struct AsciiVeil: View, Equatable {
    let palette: SalioPalette
    let seed: Int

    var body: some View {
        Canvas(rendersAsynchronously: false) { context, size in
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .color(palette.card.opacity(0.62))
            )

            let glyphs: [(Int, GraphicsContext.ResolvedText)] = [
                (72, context.resolve(Text("·").font(.system(size: 10.5, weight: .regular, design: .monospaced)).foregroundStyle(palette.ink.opacity(0.36)))),
                (86, context.resolve(Text(":").font(.system(size: 9, weight: .regular, design: .monospaced)).foregroundStyle(palette.ink.opacity(0.30)))),
                (95, context.resolve(Text("+").font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(palette.signal.opacity(0.72)))),
                (100, context.resolve(Text("/").font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundStyle(palette.ink.opacity(0.34)))),
            ]
            RefractedReticleSurface.drawAsciiScatter(
                in: &context,
                size: size,
                seed: seed,
                step: CGSize(width: 17, height: 15),
                emptyPercent: 42,
                glyphs: glyphs
            )
        }
    }
}

extension View {
    func mapBlurReveal<Trigger: Equatable>(
        palette: SalioPalette,
        trigger: Trigger
    ) -> some View {
        modifier(MapBlurRevealModifier(palette: palette, trigger: trigger))
    }
}

/// A `+` that sweeps along a short dotted track beside a playful word that changes every few seconds.
struct AsciiLoader: View {
    let palette: SalioPalette
    /// Read by VoiceOver instead of the changing words.
    let label: String
    let words: [String]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let cells = 6
    private static let interval = 0.14
    private static let ticksPerWord = 13

    var body: some View {
        TimelineView(.periodic(from: .now, by: Self.interval)) { timeline in
            let tick = Int(timeline.date.timeIntervalSinceReferenceDate / Self.interval)
            HStack(spacing: 10) {
                Text(Self.frame(reduceMotion ? 2 : tick))
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(palette.signal)
                Text(words[(tick / Self.ticksPerWord) % words.count])
                    .font(.subheadline)
                    .foregroundStyle(palette.muted)
                    .lineLimit(1)
                    .contentTransition(.opacity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }

    /// Bounces the `+` back and forth, with `:` either side of it.
    static func frame(_ tick: Int) -> String {
        let period = (cells - 1) * 2
        let step = tick % period
        let position = step < cells ? step : period - step
        return (0..<cells).map { cell in
            switch abs(cell - position) {
            case 0: "+"
            case 1: ":"
            default: "·"
            }
        }
        .joined(separator: " ")
    }
}

/// Stitching down the fold of the open Duo, like the binding of a book.
struct BookSpine: View {
    let palette: SalioPalette

    var body: some View {
        Canvas { context, size in
            let stitch = context.resolve(
                Text(":").font(.system(size: 9, design: .monospaced)).foregroundStyle(palette.muted.opacity(0.45))
            )
            var y: CGFloat = 10
            while y < size.height {
                context.draw(stitch, at: CGPoint(x: size.width / 2, y: y), anchor: .center)
                y += 18
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Dot leaders that join a name to its value, like a book's contents page.
struct DotLeader: View {
    let color: Color

    var body: some View {
        // A one-space base keeps the text baseline without asking for the dots' full width.
        Text(" ")
            .frame(maxWidth: .infinity)
            .overlay(alignment: .leading) {
                Text(String(repeating: "· ", count: 60))
                    .foregroundStyle(color)
                    .fixedSize()
            }
            .clipped()
            .font(.system(.caption, design: .monospaced))
            .accessibilityHidden(true)
    }
}

/// Marks a Nearby row with the same number as its map pin, like an atlas index.
/// Unselected is an ink outline; selected fills with the signal colour.
struct IndexMarker: View {
    var number: Int?
    var symbol: String?
    let selected: Bool
    let palette: SalioPalette
    var size: CGFloat = 28

    var body: some View {
        Group {
            if let number {
                Text("\(number)")
                    .font(.system(size: size * 0.46, weight: .semibold, design: .monospaced))
            } else if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.6, weight: .medium))
            }
        }
        .foregroundStyle(selected ? palette.onCTA : (number == nil ? palette.leaveBy : palette.ink))
        .frame(width: size, height: size)
        .background(Circle().fill(selected ? palette.signal : (number == nil ? .clear : palette.card)))
        .overlay {
            if number != nil {
                Circle().strokeBorder(selected ? palette.signal : palette.ink, lineWidth: 1.5)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Salio's first moment on a cold launch: a dot-matrix waveform that swells out of one line of dots,
/// tipped with ASCII marks, while one refraction wave passes through before it fades into the feed.
/// It never takes taps or blocks loading.
struct SalioOpening: View {
    let onFinish: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.scenePhase) private var scenePhase
    /// Set once the app is active, after iOS's launch zoom, so the wave rises where it can be seen.
    @State private var start: Date?
    @State private var fading = false

    private static let wobble: TimeInterval = 0.7

    private var animates: Bool {
        !reduceMotion && !voiceOver && contrast != .increased
    }

    var body: some View {
        let dark = colorScheme == .dark
        TimelineView(.animation(paused: !animates)) { timeline in
            GeometryReader { proxy in
                let size = proxy.size
                let elapsed = start.map { max(timeline.date.timeIntervalSince($0), 0) } ?? 0
                let t = min(elapsed / Self.wobble, 1)
                let eased = 1 - pow(1 - t, 3)
                ZStack {
                    // Equatable, so the dim grid is drawn once and only the wave redraws each frame.
                    OpeningGrid(dark: dark, showsField: contrast != .increased)
                        .equatable()
                    if contrast != .increased {
                        OpeningWave(dark: dark, rise: animates ? eased : 1, time: animates ? elapsed : 0)
                    }
                }
                .layerEffect(
                    ShaderLibrary.frostedRefraction(
                        .float2(CGPoint(x: size.width * 0.5, y: size.height * 0.5)),
                        .float(Float(eased * hypot(size.width, size.height) * 0.62)),
                        .float(64),
                        .float(Float(sin(t * .pi)) * 0.85),
                        .float(1.8)
                    ),
                    maxSampleOffset: CGSize(width: 20, height: 20),
                    isEnabled: animates && t < 1
                )
            }
        }
        .ignoresSafeArea()
        .opacity(fading ? 0 : 1)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active, start == nil { start = .now }
        }
        .task(id: start) {
            guard start != nil else { return }
            if animates { try? await Task.sleep(for: .milliseconds(550)) }
            withAnimation(.easeOut(duration: 0.3)) { fading = true }
            try? await Task.sleep(for: .milliseconds(320))
            onFinish()
        }
    }
}

/// The opening's dot pitch, shared by the grid and the wave so their dots line up.
private let openingStep: CGFloat = 14

/// The launch background with a faint dot grid. The opening's colours are the same for every theme,
/// because the launch screen before it can't know the theme; they change only between light and dark.
private struct OpeningGrid: View, Equatable {
    let dark: Bool
    let showsField: Bool

    var body: some View {
        let ground = Color(hex: dark ? 0x0B0C10 : 0xF2F3F6)
        let dot = Color(hex: dark ? 0x2A2C38 : 0xD6D8E2)
        Canvas(rendersAsynchronously: false) { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(ground))
            guard showsField else { return }
            var dots = Path()
            for row in 0...Int(size.height / openingStep) {
                for col in 0...Int(size.width / openingStep) {
                    let x = CGFloat(col) * openingStep + openingStep / 2
                    let y = CGFloat(row) * openingStep + openingStep / 2
                    dots.addEllipse(in: CGRect(x: x - 1.2, y: y - 1.2, width: 2.4, height: 2.4))
                }
            }
            context.fill(dots, with: .color(dot))
        }
    }
}

/// A waveform of dots: each column's height breathes over time, dots swell towards the middle of the
/// wave, a bright band runs along the centre line, the fringe shifts hue across the screen, and some
/// peaks carry an amber, green or lavender mark.
private struct OpeningWave: View {
    let dark: Bool
    /// 0 is a single line of dots, 1 is the full wave.
    let rise: Double
    let time: TimeInterval

    var body: some View {
        // Centre to edge: core, light, body, fringe. In light mode the core is the darkest ink instead.
        let bands = dark
            ? [Color(hex: 0xE4E6FF), Color(hex: 0xB9BEFF), Color(hex: 0x8A93F7)]
            : [Color(hex: 0x2E2A78), Color(hex: 0x4B47B8), Color(hex: 0x7C82E8)]
        // The fringe splits like light through a prism: green, lavender, then amber across the screen.
        let fringes = dark
            ? [Color(hex: 0x3E9F74), Color(hex: 0x575DA8), Color(hex: 0xC4843A)]
            : [Color(hex: 0x7CC4A0), Color(hex: 0xB4B7EA), Color(hex: 0xE8B579)]
        let marks = dark
            ? [Color(hex: 0xE69B42), Color(hex: 0x4CC38A), Color(hex: 0xB7AEDD)]
            : [Color(hex: 0xC87316), Color(hex: 0x1D8150), Color(hex: 0x6A5BB3)]
        Canvas(rendersAsynchronously: false) { context, size in
            let glyphs = zip(["+", ":", "*"], marks).map { glyph, color in
                context.resolve(Text(glyph).font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundStyle(color))
            }
            let columns = Int(size.width / openingStep)
            let rows = Int(size.height / openingStep)
            let centre = size.height / 2
            let reach = size.height * 0.45
            let colors = bands + fringes
            var paths = [Path](repeating: Path(), count: colors.count)

            for col in 0...columns {
                let x = CGFloat(col) * openingStep + openingStep / 2
                let u = Double(x / size.width)
                let h = RefractedReticleSurface.cellHash(row: 0, col: col, seed: 49)
                // A bell across the screen, broken into uneven spikes that drift with time.
                let bell = exp(-pow((u - 0.5) / 0.34, 2))
                let spikes = 0.55 + 0.45 * sin(u * 19 + time * 2.2) * sin(u * 7.3 - time * 1.3)
                let jitter = 0.82 + 0.18 * Double(h % 100) / 100
                let height = 0.05 + rise * 0.95 * bell * spikes * jitter
                let fringe = bands.count + min(Int(u * 3), 2)

                for row in 0...rows {
                    let y = CGFloat(row) * openingStep + openingStep / 2
                    let dy = Double(abs(y - centre) / reach)
                    guard dy < height else { continue }
                    let inside = 1 - dy / height
                    let radius = openingStep * 0.47 * CGFloat(0.4 + 0.6 * min(inside * 3, 1))
                    let band = inside < 0.16 ? fringe : dy < 0.09 ? 0 : dy < 0.2 ? 1 : 2
                    paths[band].addEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
                }

                // ASCII tips on every few peaks, once the wave has opened.
                if rise > 0.5, height > 0.3, h % 4 == 0 {
                    let tip = CGFloat(height) * reach + openingStep * 1.2
                    var mark = context
                    mark.opacity = (rise - 0.5) * 2
                    let glyph = glyphs[Int((h >> 8) % UInt64(glyphs.count))]
                    mark.draw(glyph, at: CGPoint(x: x, y: centre - tip), anchor: .center)
                    mark.draw(glyph, at: CGPoint(x: x, y: centre + tip), anchor: .center)
                }
            }
            // Fringes first, core last, so the brighter dots sit on top where they overlap.
            for (path, color) in zip(paths, colors).reversed() {
                context.fill(path, with: .color(color))
            }
        }
    }
}
