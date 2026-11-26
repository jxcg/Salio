# Salio Design System

## 1. Visual Direction

Salio is a light-first native iOS discovery app built on **Urban Utility** structure and **Frosted Glass Refraction** optics:

- **Architectural light surfaces** with automatic Dark Mode pairing—avoiding both harsh unmodulated pure white and cream/parchment palettes.
- **Stark native SF Pro typography**, tabular monospaced timing metadata, hairline rules, and 999pt pill controls.
- **Physical frosted-glass refraction** driven by a single Metal `layerEffect` shader (`frostedRefraction`) that bends light, applies soft optical frost, and produces natural warm/cool RGB dispersion only inside active touch or selection ripples.
- **Minimal calibration reticle (`+ ·`)** as a low-contrast background substrate inside focal cards so the GPU glass ripple has fine geometric points to bend and push outward while foreground copy stays crisp.

## 2. Color Palettes

Salio supports two switchable palettes in **Profile → Appearance** (`@AppStorage`, persisted on-device), each adapting automatically to Light and Dark Mode.

### Mist & Glass (Default)

Cool anodized silver-mist shell with lavender signal and warm peach-gold caustics inside the glass plane.

| Token | Light | Dark | Role |
| --- | --- | --- | --- |
| `ground` | `#F2F3F6` | `#0B0C10` | App canvas and grouped form background |
| `card` | `#FCFCFD` | `#151720` | Elevated card, search pill, and row surfaces |
| `soft` | `#E6E8EF` | `#1F2230` | Secondary pill fill and grabber |
| `border` | `#DFE2EA` | `#2A2E40` | 1pt hairlines and card outlines |
| `ink` | `#0D0F14` | `#F4F5F8` | Primary titles and solid pill CTA fill (light) |
| `muted` | `#5A5F6C` | `#9CA2B3` | Addresses, section headers, and secondary copy |
| `signal` | `#6A5BB3` | `#B7AEDD` | Active accent, match reason labels, selected pin/switch |
| `leaveBy` | `#1D8150` | `#4CC38A` | Leave-by timing emphasis |
| `causticWarm` | `#F0A670` | `#E89F6E` | Subtle sunlit glass wash inside focal cards |
| `causticCool` | `#7666C6` | `#9586E0` | Subtle lavender counter-wash inside focal cards |

### Stone & Amber

Cool London limestone mineral surface warmed by sunlit honey-amber highlights.

| Token | Light | Dark | Role |
| --- | --- | --- | --- |
| `ground` | `#EFF0EE` | `#0E0F0E` | App canvas and grouped form background |
| `card` | `#FAFBFA` | `#171917` | Elevated card, search pill, and row surfaces |
| `soft` | `#E4E6E2` | `#222522` | Secondary pill fill and grabber |
| `border` | `#DCDFDA` | `#2E322E` | 1pt hairlines and card outlines |
| `ink` | `#101211` | `#F3F4F2` | Primary titles and solid pill CTA fill (light) |
| `muted` | `#5C605D` | `#A0A5A0` | Addresses, section headers, and secondary copy |
| `signal` | `#C87316` | `#E69B42` | Active accent, match reason labels, selected pin/switch |
| `leaveBy` | `#1D8150` | `#4CC38A` | Leave-by timing emphasis |
| `causticWarm` | `#E8A54C` | `#DF9A44` | Subtle sunlit amber wash inside focal cards |
| `causticCool` | `#8272CC` | `#988AD8` | Faint cool counter-wash inside focal cards |

## 3. Typography & Layout

- **Display / Featured title:** SF Pro Display Bold (`22pt`, tight tracking, Dynamic Type scaled).
- **Row titles:** SF Pro Text Semibold (`16pt` / `.headline`).
- **Secondary copy:** SF Pro Text Regular (`.subheadline`, `muted`).
- **Timing & micro-labels:** SF Mono / `.monospacedDigit()` for leave-by times and compact metadata.
- **Corner radii:** `999pt` (`Capsule`) for search bar and primary action pills; `20pt` for focal cards; `16pt` for grouped row containers.
- **Touch targets:** At least `44×44pt` for toolbar buttons and map pins.
- **iPhone Duo book layout:** When unfolded, Salio reads the fold from the display's division region and splits the inner display 50/50 like an open book. The right page keeps the closed cover's Nearby feed and toolbar, so cards, line wraps, and rhythm carry across the fold. The left page pairs a muted Apple Map crop (`240pt`) with the frosted Timing / Place details card (`Open in Maps` for live places) and an **Also nearby** list of the three places closest to the selection, with distances. iPad and other regular-width windows keep the balanced split view with a `270–340pt` context column.

## 4. Optical Frosted-Glass Refraction

- **Two-plane legibility:** `RefractedReticleSurface` renders the ambient caustic wash and a deterministically scattered `+ · . : /` reticle (per-card hash seed with empty cells and subtle jitter so no mechanical grid or diagonal repeats appear) into one static `Canvas` layer underneath sharp foreground SwiftUI text.
- **Single GPU pass:** When triggered by a tap, selection change, or re-ranking promotion, `TimelineView(.animation(paused: !isRippling))` advances a `0.62s` radial ripple through `ShaderLibrary.frostedRefraction`:
  - Displaces pixels radially along the smooth cosine wave band so the `+ ·` reticle visibly moves and bends on the wave.
  - Averages a 5-tap frosted optical blur scaled by wave intensity.
  - Samples Red (`0.72×`), Green (`1.0×`), and Blue (`1.30×`) along the lens offset so natural warm/cool edge dispersion emerges only from bending light—never painted on as static red/blue chrome.
- **Scoped per-card ripple:** Each `FrostedGlassCard` manages its own tap origin and ripple state (`SpatialTapGesture`) so a tap ripples **only** the card you touched—never sibling cards.
- **Map blur-to-reveal ASCII veil:** When the Duo map rail or full-screen map appears or pans to a newly selected place, `MapBlurRevealModifier` briefly (`0.85s`) resolves a `12pt → 0pt` blur alongside a shifting organic `+ · : /` ASCII scatter veil, then pauses completely with zero idle redraws (disabled under `Reduce Motion`, `VoiceOver`, and `Increase Contrast`).
- **Subtle Duo paper-unfold play:** While closed, the left rail pre-arms tucked toward the center crease (`-11° / -13°` trailing-anchored hinge tilt, soft hinge crease shade, map held under its ASCII veil so there is no sharp-to-blurry pop). After a `180ms` hardware display handoff on `closed → fullyOpen`, the map swings open first (`.spring(response: 0.52, dampingFraction: 0.72)`) as its ASCII blur-to-reveal veil clears, followed `110ms` later by the frosted context card (`.spring(response: 0.58, dampingFraction: 0.70)`) and one gentle frosted ripple on the context card alone—while the right-hand feed stays anchored at its exact `350pt` closed width. Disabled under `Reduce Motion`, `VoiceOver`, and `Increase Contrast`.
- **Zero idle burn:** Outside active transitions (`0.62s` frosted ripple, `0.85s` map reveal), `TimelineView` pauses and `.layerEffect(..., isEnabled: false)` bypasses the shader completely.

- **Quiet ASCII touches:** While Salio finds your location or searches, `AsciiLoader` sweeps a `+` along a short `· : + : ·` track beside a playful status word that changes every ~1.8s (`Rummaging…`, `Moseying…`, `Getting our bearings…`) (static under `Reduce Motion`; VoiceOver reads a plain label such as “Finding places”). On the open Duo, `BookSpine` stitches a faint `:` column down the fold like a book's binding, and **Also nearby** rows join names to distances with `DotLeader` dots like a contents page. None of these sit over text or take taps.

## 5. Restraint & Accessibility Rules

- **No ASCII clipart:** Never use ASCII illustrations for categories, icons, pins, toggles, or progress bars; use native SF Symbols.
- **Clean launch screen:** Keep `UILaunchScreen` blank and native—zero splash art or ASCII on launch.
- **No permanent aberration:** Dispersion returns to `0` at rest so titles and body copy stay razor-sharp.
- **Accessibility first:**
  - The reticle and glass shader are marked `.accessibilityHidden(true)`.
  - When `accessibilityReduceMotion`, `accessibilityVoiceOverEnabled`, or `colorSchemeContrast == .increased` is active, ripples and refraction disable automatically and cards fall back to high-contrast static surfaces.
