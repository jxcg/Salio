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
                            .float(2.6),
                            .float(1)
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

    private static func cellHash(row: Int, col: Int, seed: Int) -> UInt64 {
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
    /// Whether the reveal also plays when the map first appears, not only when `trigger` changes.
    let revealsOnAppear: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var revealStart: Date?
    @State private var isRevealing = false
    @State private var appeared = false

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
            let firstRun = !appeared
            appeared = true
            guard allowsReveal, revealsOnAppear || !firstRun else {
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
        trigger: Trigger,
        revealsOnAppear: Bool = true
    ) -> some View {
        modifier(MapBlurRevealModifier(palette: palette, trigger: trigger, revealsOnAppear: revealsOnAppear))
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

/// A `@` that sends a ring of the opening's ASCII characters out around it, like sonar, lighting up
/// the `+` places it passes. It sits in empty space, never behind text, and holds still under Reduce
/// Motion, VoiceOver and Increase Contrast.
struct AsciiRadar: View {
    let palette: SalioPalette

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.colorSchemeContrast) private var contrast

    private static let cell: CGFloat = 14
    /// Each ring takes `sweep` seconds to leave the frame, then the radar rests before the next.
    private static let sweep: TimeInterval = 2.2, rest: TimeInterval = 0.8
    /// The ring's depth in cells, and how long a place stays lit after the ring passes it.
    private static let band = 3.0, glow: TimeInterval = 0.9
    /// Indexes into `AsciiReveal.ramp`: `@#*+=-:.`.
    private static let you = 0, lit = 2, place = 3

    var body: some View {
        let animates = !reduceMotion && !voiceOver && contrast != .increased
        // 30 fps is plenty: the ring moves a whole cell at a time.
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !animates)) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Self.sweep + Self.rest)
            Canvas { context, size in draw(in: context, size: size, phase: animates ? phase : nil) }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Draws one frame; `phase` is the time into the current sweep, or nil for the still frame.
    private func draw(in context: GraphicsContext, size: CGSize, phase: TimeInterval?) {
        let cell = Self.cell
        let columns = Int(size.width / cell), rows = Int(size.height / cell)
        guard columns > 2, rows > 2 else { return }
        let inset = CGPoint(x: (size.width - CGFloat(columns) * cell) / 2, y: (size.height - CGFloat(rows) * cell) / 2)
        let centre = (row: rows / 2, col: columns / 2)
        // The ring eases out from the centre until it has left the farthest corner.
        let reach = hypot(Double(columns), Double(rows)) / 2 + Self.band
        func ring(at time: TimeInterval) -> Double { (1 - pow(1 - min(time / Self.sweep, 1), 2)) * reach }
        let radius = phase.map { $0 < Self.sweep ? ring(at: $0) : -1 } ?? -1

        var dots = Path(), trail = Path(), front = Path(), places = Path(), signal = Path()
        for row in 0..<rows {
            for col in 0..<columns {
                let at = CGAffineTransform(
                    translationX: inset.x + (CGFloat(col) + 0.5) * cell,
                    y: inset.y + (CGFloat(row) + 0.5) * cell
                )
                if row == centre.row, col == centre.col {
                    signal.addPath(AsciiReveal.glyphs[Self.you], transform: at)
                    continue
                }
                let distance = hypot(Double(col - centre.col), Double(row - centre.row))
                let hash = AsciiReveal.hash(row: row, col: col)

                // About one cell in twenty is a place, never right next to you.
                if hash % 20 == 0, distance > 2.5 {
                    // When the ring reached this place, worked back from how far it is.
                    let passed = Self.sweep * (1 - (1 - min(distance / reach, 1)).squareRoot())
                    if let phase, phase >= passed, phase - passed < Self.glow {
                        signal.addPath(AsciiReveal.glyphs[Self.lit], transform: at)
                    } else {
                        places.addPath(AsciiReveal.glyphs[Self.place], transform: at)
                    }
                    continue
                }

                // Inside the ring the characters thin out from `*` at its edge to `.` behind it.
                let behind = radius - distance
                if behind >= 0, behind < Self.band, Double((hash >> 8) % 100) / 100 > behind / Self.band * 0.7 {
                    let level = min(2 + Int(behind / Self.band * 6), AsciiReveal.ramp.count - 1)
                    if level < 4 {
                        front.addPath(AsciiReveal.glyphs[level], transform: at)
                    } else {
                        trail.addPath(AsciiReveal.glyphs[level], transform: at)
                    }
                } else {
                    let point = CGPoint(x: at.tx, y: at.ty)
                    dots.addEllipse(in: CGRect(x: point.x - 1, y: point.y - 1, width: 2, height: 2))
                }
            }
        }
        context.fill(dots, with: .color(palette.border))
        context.fill(trail, with: .color(palette.muted.opacity(0.6)))
        context.fill(front, with: .color(palette.muted))
        // Places take a faint accent, so they never read as part of the ring's grey `+`.
        context.fill(places, with: .color(palette.signal.opacity(0.5)))
        context.fill(signal, with: .color(palette.signal))
    }
}

/// A `#` that walks city blocks from `@` (you) to one nearby place after another, leaving a `: .`
/// trail, and lights each place from `+` to `*` when it gets there. It sits in empty space, never
/// behind text, and shows one finished route, still, under Reduce Motion, VoiceOver and Increase Contrast.
struct AsciiRoute: View {
    let palette: SalioPalette

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.colorSchemeContrast) private var contrast

    private static let cell: CGFloat = 14
    /// Each walk takes `walk` seconds, then the lit place holds for `hold` before the next walk.
    private static let walk: TimeInterval = 1.6, hold: TimeInterval = 0.8
    /// Where the places sit, as fractions of the grid away from you.
    private static let stops: [(x: Double, y: Double)] = [(0.36, -0.32), (-0.34, 0.3), (0.28, 0.36)]
    /// Indexes into `AsciiReveal.ramp`: `@#*+=-:.`.
    private static let you = 0, walker = 1, lit = 2, place = 3, near = 6, far = 7

    var body: some View {
        let animates = !reduceMotion && !voiceOver && contrast != .increased
        // 30 fps is plenty: the walker moves a whole cell at a time.
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !animates)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in draw(in: context, size: size, time: animates ? time : nil) }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Draws one frame; `time` is the clock, or nil for the still frame.
    private func draw(in context: GraphicsContext, size: CGSize, time: TimeInterval?) {
        let cell = Self.cell
        let columns = Int(size.width / cell), rows = Int(size.height / cell)
        guard columns > 4, rows > 4 else { return }
        let inset = CGPoint(x: (size.width - CGFloat(columns) * cell) / 2, y: (size.height - CGFloat(rows) * cell) / 2)
        let start = (row: rows / 2, col: columns / 2)
        let places = Self.stops.map { stop in
            (row: min(max(start.row + Int(stop.y * Double(rows)), 0), rows - 1),
             col: min(max(start.col + Int(stop.x * Double(columns)), 0), columns - 1))
        }

        // Which place this walk heads for, and how far into the walk it is.
        let leg = Self.walk + Self.hold
        let elapsed = time.map { $0.truncatingRemainder(dividingBy: leg * Double(places.count)) } ?? leg - 0.01
        let target = Int(elapsed / leg)
        let into = elapsed - Double(target) * leg

        // Along the row first, then down the column, like walking round a block.
        let goal = places[target]
        var route = [Int]()
        var col = start.col, row = start.row
        while col != goal.col { col += goal.col > col ? 1 : -1; route.append(row * columns + col) }
        while row != goal.row { row += goal.row > row ? 1 : -1; route.append(row * columns + col) }
        let steps = min(Int(into / Self.walk * Double(route.count)), route.count)
        let arrived = steps == route.count

        // What each marked cell shows; everything else is a faint dot.
        var marks = [Int: (glyph: Int, signal: Bool)]()
        for (index, cell) in route.prefix(steps).enumerated() {
            let behind = steps - 1 - index
            marks[cell] = behind == 0 && !arrived ? (Self.walker, true) : (behind < 4 ? Self.near : Self.far, false)
        }
        marks[start.row * columns + start.col] = (Self.you, true)

        var dots = Path(), trail = Path(), signal = Path(), waiting = Path()
        for place in places {
            let index = place.row * columns + place.col
            if index == route.last, arrived {
                marks[index] = (Self.lit, true)
            } else {
                marks[index] = nil
                waiting.addPath(AsciiReveal.glyphs[Self.place], transform: transform(place.row, place.col, inset))
            }
        }
        for row in 0..<rows {
            for col in 0..<columns {
                let at = transform(row, col, inset)
                if let mark = marks[row * columns + col] {
                    if mark.signal {
                        signal.addPath(AsciiReveal.glyphs[mark.glyph], transform: at)
                    } else {
                        trail.addPath(AsciiReveal.glyphs[mark.glyph], transform: at)
                    }
                } else if !places.contains(where: { $0.row == row && $0.col == col }) {
                    dots.addEllipse(in: CGRect(x: at.tx - 1, y: at.ty - 1, width: 2, height: 2))
                }
            }
        }
        context.fill(dots, with: .color(palette.border))
        context.fill(trail, with: .color(palette.muted))
        context.fill(waiting, with: .color(palette.signal.opacity(0.5)))
        context.fill(signal, with: .color(palette.signal))
    }

    private func transform(_ row: Int, _ col: Int, _ inset: CGPoint) -> CGAffineTransform {
        CGAffineTransform(translationX: inset.x + (CGFloat(col) + 0.5) * Self.cell, y: inset.y + (CGFloat(row) + 0.5) * Self.cell)
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

/// Salio's first moment on a cold launch: once the app is active, an `AsciiReveal` in a random shape and
/// colour mix bursts the launch screen open onto the feed, riding one refraction wave, with no fade.
/// It only tears through to the feed once the feed's first load is final, so it never shows data that is
/// about to change. While Nearby is still loading, the ring breathes on the closed sheet; if the load is
/// done in time it tears open, and after `maxWait` or a tap it bursts across the closed sheet and fades.
/// Its colours follow light and dark but not the theme, because the launch screen before it can't know
/// the theme. Under Reduce Motion, VoiceOver or Increase Contrast, the launch colour simply fades.
struct SalioOpening: View {
    /// How the opening hands over to a feed that is ready. While the feed is still loading, both fade.
    enum Style: String, CaseIterable, Identifiable {
        /// The burst tears the launch screen open onto the results.
        case tear
        /// The burst runs across the closed launch screen, which then fades onto the results.
        case fade

        var id: String { rawValue }
        var displayName: String { self == .tear ? "Tear open" : "Burst and fade" }
        static var storageKey: String { SalioTestStore.scopedKey("salioOpeningStyle") }
    }

    /// Whether the feed has finished its first load.
    let ready: Bool
    /// Whether that load found places. Only then does Tear open uncover the feed; a failure, no results,
    /// or no location fades instead, so the tear never lands on an empty or error state.
    let found: Bool
    let onFinish: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(Style.storageKey) private var style: Style = .tear
    /// Set once the app is active, after iOS's launch zoom, so the reveal plays where it can be seen.
    @State private var start: Date?
    /// When the ring was released: the feed became ready, `maxWait` passed, or someone tapped.
    @State private var releasedAt: Date?
    /// Whether the release tears open onto the feed, which only happens once the feed is ready.
    @State private var tears = false
    @State private var fading = false
    /// Shape and colours are picked once per launch, independently of each other.
    @State private var shape = AsciiReveal.Shape.allCases.randomElement() ?? .starburst
    @State private var accents = Self.mixes.randomElement() ?? Self.mixes[0]

    private static let duration: TimeInterval = 0.6
    /// The longest the ring breathes before tearing open anyway.
    private static let maxWait: TimeInterval = 2
    /// While waiting, the ring grows to `hold` at its normal speed, then breathes around it.
    private static let hold = 0.14, breath = 0.035, breathPeriod: TimeInterval = 1.1
    /// Accent colours as (dark, light) pairs: prism, ember, and tide.
    private static let mixes: [[(dark: UInt32, light: UInt32)]] = [
        [(0x4CC38A, 0x1D8150), (0x9AA0F5, 0x5A55C8), (0xE69B42, 0xC87316)],
        [(0xE69B42, 0xC87316), (0xE8805A, 0xC4562E), (0xB7AEDD, 0x6A5BB3)],
        [(0x4CC38A, 0x1D8150), (0x9586E0, 0x7666C6), (0x9CA2B3, 0x5A5F6C)],
    ]

    private var animates: Bool {
        !reduceMotion && !voiceOver && contrast != .increased
    }

    var body: some View {
        // Colours are worked out once here, so each frame only computes progress.
        let dark = colorScheme == .dark
        let dots = Color(hex: dark ? 0x2A2C38 : 0xD6D8E2)
        let core = Color(hex: dark ? 0xE4E6FF : 0x2E2A78)
        let inks = accents.map { Color(hex: dark ? $0.dark : $0.light) }
        TimelineView(.animation(paused: !animates || start == nil)) { timeline in
            let progress = start.map { progress(at: timeline.date, from: $0) } ?? 0
            if animates {
                AsciiReveal(
                    progress: progress,
                    shape: shape,
                    cover: Color("LaunchBackground"),
                    dots: dots,
                    core: core,
                    accents: inks,
                    opens: tears
                )
                .visualEffect { content, proxy in
                    let reach = hypot(proxy.size.width, proxy.size.height)
                    return content.layerEffect(
                        ShaderLibrary.frostedRefraction(
                            .float2(proxy.size.width / 2, proxy.size.height / 2),
                            .float((1 - pow(1 - progress, 3)) * reach * 0.62),
                            .float(64),
                            .float(sin(progress * .pi) * 0.85),
                            .float(1.8),
                            // A stronger colour split than the cards' ripple, so the pulse reads as glass.
                            .float(1.6)
                        ),
                        maxSampleOffset: CGSize(width: 20, height: 20),
                        isEnabled: progress > 0 && progress < 1
                    )
                }
            } else {
                Color("LaunchBackground")
            }
        }
        .ignoresSafeArea()
        .opacity(fading ? 0 : 1)
        // While the ring waits, a tap releases it instead of reaching the feed hidden underneath.
        .contentShape(.rect)
        .onTapGesture { releasedAt = releasedAt ?? .now }
        .allowsHitTesting(animates && releasedAt == nil)
        .accessibilityHidden(true)
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active, start == nil { start = .now }
        }
        .onChange(of: ready, initial: true) {
            guard ready, releasedAt == nil else { return }
            tears = style == .tear && found
            releasedAt = .now
        }
        .task(id: [start, releasedAt]) {
            guard let start else { return }
            do {
                if animates, releasedAt == nil {
                    // Stop waiting after `maxWait` and leave the feed's own loader to carry on.
                    try await Task.sleep(for: .seconds(max((start + Self.maxWait).timeIntervalSinceNow, 0)))
                    releasedAt = .now
                    return
                } else if animates, tears {
                    // The reveal draws nothing once it ends, so the opening can just leave.
                    let release = release(from: start)
                    let end = release + (1 - Self.waiting(release.timeIntervalSince(start))) * Self.duration
                    try await Task.sleep(for: .seconds(max(end.timeIntervalSinceNow, 0)))
                } else {
                    // The feed isn't final yet (or motion is reduced), so fade the closed sheet instead of
                    // tearing it; the burst carries on outward while it fades.
                    let fade = animates ? Self.duration : 0.2
                    withAnimation(.easeOut(duration: fade)) { fading = true }
                    try await Task.sleep(for: .seconds(fade))
                }
                onFinish()
            } catch {
                // Cancelled because the ring was released; the next run of this task finishes instead.
            }
        }
    }

    /// When the ring stops waiting: once released, but never before the opening starts.
    private func release(from start: Date) -> Date {
        max(releasedAt ?? .distantFuture, start)
    }

    /// The reveal's progress: it grows and breathes until released, then runs on to 1 at its normal speed.
    private func progress(at date: Date, from start: Date) -> Double {
        let release = release(from: start)
        let waited = Self.waiting(min(date, release).timeIntervalSince(start))
        return min(waited + max(date.timeIntervalSince(release), 0) / Self.duration, 1)
    }

    /// Progress while waiting: the normal rise up to `hold`, then a slow breath around it.
    private static func waiting(_ elapsed: TimeInterval) -> Double {
        let rise = hold * duration
        guard elapsed > rise else { return max(elapsed, 0) / duration }
        return hold + breath * sin((elapsed - rise) / breathPeriod * 2 * .pi)
    }
}
