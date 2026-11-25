import SwiftUI

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
        #if DEBUG
        if let store = ProcessInfo.processInfo.environment["SALIO_PROFILE_TEST_STORE"] {
            return "salioAppearance.\(store)"
        }
        #endif
        return "salioAppearance"
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
                causticWarm: Color(hex: 0xE89F6E),
                causticCool: Color(hex: 0x9586E0),
                reticlePrimary: Color.white.opacity(0.22),
                reticleSecondary: Color.white.opacity(0.11),
                causticWarmOpacity: 0.16,
                causticCoolOpacity: 0.14
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
                causticWarm: Color(hex: 0xF0A670),
                causticCool: Color(hex: 0x7666C6),
                reticlePrimary: Color(hex: 0x0D0F14).opacity(0.24),
                reticleSecondary: Color(hex: 0x0D0F14).opacity(0.12),
                causticWarmOpacity: 0.22,
                causticCoolOpacity: 0.14
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
                causticWarm: Color(hex: 0xDF9A44),
                causticCool: Color(hex: 0x988AD8),
                reticlePrimary: Color.white.opacity(0.22),
                reticleSecondary: Color.white.opacity(0.11),
                causticWarmOpacity: 0.16,
                causticCoolOpacity: 0.11
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
                causticWarm: Color(hex: 0xE8A54C),
                causticCool: Color(hex: 0x8272CC),
                reticlePrimary: Color(hex: 0x101211).opacity(0.24),
                reticleSecondary: Color(hex: 0x101211).opacity(0.12),
                causticWarmOpacity: 0.22,
                causticCoolOpacity: 0.11
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
    let causticWarmOpacity: Double
    let causticCoolOpacity: Double
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
                    Gradient(colors: [palette.causticWarm.opacity(palette.causticWarmOpacity), .clear]),
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
                    Gradient(colors: [palette.causticCool.opacity(palette.causticCoolOpacity), .clear]),
                    center: coolCenter,
                    startRadius: 6,
                    endRadius: coolRadius
                )
            )

            let stepX: CGFloat = 19
            let stepY: CGFloat = 17
            let cols = Int(size.width / stepX) + 1
            let rows = Int(size.height / stepY) + 1
            let plus = context.resolve(
                Text("+").font(.system(size: 9, weight: .regular, design: .monospaced))
                    .foregroundStyle(palette.reticlePrimary)
            )
            let dot = context.resolve(
                Text("·").font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(palette.reticleSecondary)
            )
            let period = context.resolve(
                Text(".").font(.system(size: 9, weight: .regular, design: .monospaced))
                    .foregroundStyle(palette.reticleSecondary)
            )
            let colon = context.resolve(
                Text(":").font(.system(size: 8.5, weight: .regular, design: .monospaced))
                    .foregroundStyle(palette.reticleSecondary)
            )
            let slash = context.resolve(
                Text("/").font(.system(size: 8.5, weight: .regular, design: .monospaced))
                    .foregroundStyle(palette.reticlePrimary.opacity(0.65))
            )

            for row in 0..<rows {
                for col in 0..<cols {
                    let h = Self.cellHash(row: row, col: col, seed: seed)
                    let bucket = Int(h % 100)
                    guard bucket >= 44 else { continue }

                    let jitterX = CGFloat(Int((h >> 8) % 9) - 4) * 0.85
                    let jitterY = CGFloat(Int((h >> 12) % 9) - 4) * 0.85
                    let point = CGPoint(
                        x: CGFloat(col) * stepX + 10 + jitterX,
                        y: CGFloat(row) * stepY + 9 + jitterY
                    )

                    let glyph: GraphicsContext.ResolvedText
                    switch bucket {
                    case 44..<74: glyph = dot
                    case 74..<87: glyph = period
                    case 87..<95: glyph = plus
                    case 95..<98: glyph = colon
                    default: glyph = slash
                    }
                    context.draw(glyph, at: point, anchor: .center)
                }
            }
        }
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
    let rippleStart: Date?
    let rippleOrigin: UnitPoint
    var seed: Int = 0
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack(alignment: .leading) {
            RefractedReticleSurface(
                palette: palette,
                rippleStart: rippleStart,
                rippleOrigin: rippleOrigin,
                seed: seed
            )
            content()
                .padding(16)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(palette.border, lineWidth: 1)
        )
    }
}
