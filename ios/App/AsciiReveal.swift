import CoreText
import SwiftUI

#if canImport(UIKit)
import UIKit
private typealias PlatformFont = UIFont
#elseif canImport(AppKit)
import AppKit
private typealias PlatformFont = NSFont
#endif

/// A sheet of dots that a front of ASCII characters bursts across, uncovering whatever is behind it.
///
/// It is a pure function of `progress`: at 0 the sheet covers everything, at 1 it is fully open and draws
/// nothing, so any clock can drive it, such as a `TimelineView`, a gesture, or a scroll position.
///
///     content.overlay {
///         AsciiReveal(progress: progress, shape: .bloom, cover: .black, dots: .gray, core: .white, accents: [.green, .orange])
///     }
struct AsciiReveal: View {
    /// How the front spreads out from the centre.
    enum Shape: CaseIterable {
        case starburst, bloom, diamond, pinwheel, rift

        /// How far the front travels to reach the point (`x`, `y`), both measured from the centre as
        /// fractions of the screen diagonal, so every shape looks the same on any screen size.
        func distance(_ x: Double, _ y: Double) -> Double {
            let radius = hypot(x, y), angle = atan2(y, x)
            return switch self {
            case .starburst: radius / (1 + 0.1 * sin(angle * 7) + 0.06 * sin(angle * 13 + 1))
            case .bloom: radius / (1 + 0.2 * cos(angle * 5))
            case .diamond: (abs(x) + abs(y)) * 0.75
            case .pinwheel: radius + ((angle + .pi) / (2 * .pi) * 3).truncatingRemainder(dividingBy: 1) * 0.1
            case .rift: abs(y) * (1 + 0.25 * sin(x * 40)) + abs(x) * 0.25
            }
        }
    }

    var progress: Double
    var shape: Shape = .starburst
    /// The sheet's colour, usually the launch screen's background.
    var cover: Color
    /// The sheet's faint dot grid.
    var dots: Color
    /// The densest characters, right at the front.
    var core: Color
    /// The trailing characters, split into sectors around the centre.
    var accents: [Color]
    /// Whether the front tears the sheet open. When false, the characters burst across a sheet that stays
    /// closed, so nothing behind it shows, and the caller fades the sheet away itself.
    var opens = true

    private static let cell: CGFloat = 14
    /// Densest first: the front is `@`, and the trail behind it thins out to `.`.
    private static let ramp = Array("@#*+=-:.")
    /// The front's depth, as a fraction of the diagonal: the sheet tears open 35% of the way in, and
    /// the trail of characters runs on over the uncovered content for the rest.
    private static let depth = 0.22, tear = 0.35
    /// The torn edge thins out across this much of the depth, in `feather` steps, so what's behind it
    /// fades in under the front instead of being cut out.
    private static let softness = 0.4, feather = 6

    var body: some View {
        Canvas { context, size in draw(in: context, size: size) }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func draw(in context: GraphicsContext, size: CGSize) {
        let cell = Self.cell
        let columns = Int(size.width / cell) + 1, rows = Int(size.height / cell) + 1
        let diagonal = hypot(size.width, size.height)
        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
        func point(_ row: Int, _ col: Int) -> CGPoint {
            CGPoint(x: (CGFloat(col) + 0.5) * cell, y: (CGFloat(row) + 0.5) * cell)
        }

        // How far the front must travel to reach each cell, with a little jitter so its edge is ragged.
        var reach = [Double](), hashes = [UInt64]()
        reach.reserveCapacity(rows * columns)
        hashes.reserveCapacity(rows * columns)
        for row in 0..<rows {
            for col in 0..<columns {
                let p = point(row, col), hash = Self.hash(row: row, col: col)
                let jitter = Double(hash % 100) / 100 * 1.5 * cell / diagonal
                reach.append(shape.distance((p.x - centre.x) / diagonal, (p.y - centre.y) / diagonal) + jitter)
                hashes.append(hash)
            }
        }
        // Eases out, and ends once the trail has passed the furthest cell, so nothing is left at 1.
        let front = ((reach.max() ?? 0) + Self.depth) * (1 - pow(1 - min(max(progress, 0), 1), 2))

        // `sheets[n]` is covered n/`feather` of the way; the last one is solid and carries the dot grid.
        var sheets = [Path](repeating: Path(), count: Self.feather + 1), grid = Path()
        var inks = [Path](repeating: Path(), count: accents.count + 1)
        for row in 0..<rows {
            // Neighbouring cells with the same cover join into one rectangle, so no seams show between them.
            var run: (step: Int, start: Int)?
            for col in 0...columns {
                let index = row * columns + col
                let behind = col < columns ? (front - reach[index]) / Self.depth : 1
                // The cell past the row's end is open, so it closes the last run.
                let step = col < columns ? coverStep(behind: behind) : 0
                if step != run?.step {
                    if let run, run.step > 0 {
                        sheets[run.step].addRect(CGRect(x: CGFloat(run.start) * cell, y: CGFloat(row) * cell, width: CGFloat(col - run.start) * cell, height: cell))
                    }
                    run = (step, col)
                }
                if step == Self.feather {
                    let p = point(row, col)
                    grid.addEllipse(in: CGRect(x: p.x - 1.2, y: p.y - 1.2, width: 2.4, height: 2.4))
                }

                // The trail thins out the further a cell is behind the front.
                guard col < columns, behind > 0, behind < 1, Double((hashes[index] >> 8) % 1000) / 1000 > behind * 0.9 else { continue }
                let level = min(Int(behind * Double(Self.ramp.count)), Self.ramp.count - 1)
                let p = point(row, col)
                let ink = level < 2 || accents.isEmpty ? 0 : 1 + sector(of: p, around: centre, hash: hashes[index])
                inks[ink]
                    .addPath(Self.glyphs[level], transform: CGAffineTransform(translationX: p.x, y: p.y))
            }
        }

        for (step, sheet) in sheets.enumerated().dropFirst() {
            context.fill(sheet, with: .color(cover.opacity(Double(step) / Double(Self.feather))))
        }
        context.fill(grid, with: .color(dots))
        for (ink, color) in zip(inks, [core] + accents) {
            context.fill(ink, with: .color(color))
        }
    }

    /// How covered a cell is, from 0 (open) to `feather` (solid): solid ahead of the torn edge, open
    /// behind it, and in steps across the edge. A sheet that doesn't open stays solid.
    private func coverStep(behind: Double) -> Int {
        guard opens else { return Self.feather }
        let amount = min(max(0.5 + (Self.tear - behind) / Self.softness, 0), 1)
        return Int((amount * Double(Self.feather)).rounded(.up))
    }

    /// A stable pseudo-random number per cell (SplitMix64), so the ragged edge and trail never flicker.
    private static func hash(row: Int, col: Int) -> UInt64 {
        var h = UInt64(bitPattern: Int64(row &* 73_856_093 ^ col &* 19_349_663))
        h ^= h >> 30
        h &*= 0xBF58_476D_1CE4_E5B9
        h ^= h >> 27
        h &*= 0x94D0_49BB_1331_11EB
        return h ^ (h >> 31)
    }

    /// Which accent a cell takes, by its angle around the centre, with jittered edges so sectors blend.
    private func sector(of p: CGPoint, around centre: CGPoint, hash: UInt64) -> Int {
        let turn = (atan2(p.y - centre.y, p.x - centre.x) + .pi) / (2 * .pi) * Double(accents.count)
        return (Int(turn + Double((hash >> 20) % 100) / 250)) % accents.count
    }

    /// The ramp as outlines centred on the origin, made once, so a frame fills one path per colour instead
    /// of typesetting each character.
    private static let glyphs: [Path] = {
        let font = PlatformFont.monospacedSystemFont(ofSize: 13, weight: .bold) as CTFont
        let middle = (CTFontGetAscent(font) - CTFontGetDescent(font)) / 2
        return ramp.map { character in
            var unit = character.utf16.first ?? 0, glyph = CGGlyph()
            CTFontGetGlyphsForCharacters(font, &unit, &glyph, 1)
            let advance = CTFontGetAdvancesForGlyphs(font, .horizontal, &glyph, nil, 1)
            // Flip to SwiftUI's downward y and centre the character in its line, like Text at a `.center` anchor.
            var flip = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: -advance / 2, ty: middle)
            return CTFontCreatePathForGlyph(font, glyph, &flip).map { Path($0) } ?? Path()
        }
    }()
}
