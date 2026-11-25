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
    let rippleOrigin: UnitPoint
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
                let origin = CGPoint(x: rippleOrigin.x * size.width, y: rippleOrigin.y * size.height)
                let strength = active ? Float(sin(t * .pi)) : 0

                reticleCanvas
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

    private var reticleCanvas: some View {
        Canvas(rendersAsynchronously: false) { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(palette.card))

            guard contrast != .increased else { return }

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
            Self.drawAsciiScatter(
                in: &context,
                size: size,
                seed: seed,
                step: CGSize(width: 19, height: 17),
                emptyPercent: 44,
                glyphs: glyphs
            )
        }
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
    @State private var rippleOrigin = UnitPoint(x: 0.55, y: 0.48)
    @State private var cardSize: CGSize = .zero

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
            .onGeometryChange(for: CGSize.self) { proxy in
                proxy.size
            } action: { newSize in
                cardSize = newSize
            }
            .simultaneousGesture(
                SpatialTapGesture().onEnded { value in
                    let width = max(cardSize.width, 1)
                    let height = max(cardSize.height, 1)
                    rippleOrigin = UnitPoint(
                        x: min(max(value.location.x / width, 0.08), 0.92),
                        y: min(max(value.location.y / height, 0.08), 0.92)
                    )
                    rippleStart = Date()
                },
                isEnabled: tapToRipple
            )
            .onChange(of: rippleTrigger) {
                rippleOrigin = UnitPoint(x: 0.55, y: 0.48)
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
    private struct TaskKey: Equatable {
        let trigger: Trigger
        let hold: Bool
    }

    let palette: SalioPalette
    let trigger: Trigger
    let hold: Bool

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
        let holding = allowsReveal && hold
        TimelineView(.animation(paused: !(isRevealing && allowsReveal && !holding))) { timeline in
            let progress: Double? = holding ? 0 : (isRevealing ? revealProgress(at: timeline.date) : nil)
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
                        mapAsciiVeil(seed: frameSeed)
                            .opacity(veilOpacity)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
        }
        .task(id: TaskKey(trigger: trigger, hold: hold)) {
            guard allowsReveal, !hold else {
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

    private func mapAsciiVeil(seed: Int) -> some View {
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
        hold: Bool = false
    ) -> some View {
        modifier(MapBlurRevealModifier(palette: palette, trigger: trigger, hold: hold))
    }
}
