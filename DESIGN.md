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
- **iPhone Duo compact map rail:** When unfolded, the left column stays constrained to a compact rail (`270–340pt`, ~34% of the display) pairing a live muted Apple Map crop (`180pt`) with a frosted-glass Timing / Place details card (`Open in Maps` for live places), while the right-hand Nearby feed locks to its measured closed-Duo cover width (`compactFeedWidth`, defaulting to `382pt`) so card widths, line wraps, and vertical rhythm stay identical across fold and unfold.

## 4. Optical Frosted-Glass Refraction

- **Two-plane legibility:** `RefractedReticleSurface` renders the ambient caustic wash and a deterministically scattered `+ · . : /` reticle (per-card hash seed with empty cells and subtle jitter so no mechanical grid or diagonal repeats appear) into one static `Canvas` layer underneath sharp foreground SwiftUI text.
- **Single GPU pass:** When triggered by a tap, selection change, or re-ranking promotion, `TimelineView(.animation(paused: !isRippling))` advances a `0.62s` radial ripple through `ShaderLibrary.frostedRefraction`:
  - Displaces pixels radially along the smooth cosine wave band so the `+ ·` reticle visibly moves and bends on the wave.
  - Averages a 5-tap frosted optical blur scaled by wave intensity.
  - Samples Red (`0.72×`), Green (`1.0×`), and Blue (`1.30×`) along the lens offset so natural warm/cool edge dispersion emerges only from bending light—never painted on as static red/blue chrome.
- **Scoped per-card ripple:** Each `FrostedGlassCard` manages its own tap origin and ripple state (`SpatialTapGesture`) so a tap ripples **only** the card you touched—never sibling cards.
- **Map blur-to-reveal ASCII veil:** When the Duo map rail or full-screen map appears or pans to a newly selected place, `MapBlurRevealModifier` briefly (`0.60s`) resolves a `10pt → 0pt` blur alongside a shifting organic `+ · : /` ASCII scatter veil, then pauses completely with zero idle redraws (disabled under `Reduce Motion`, `VoiceOver`, and `Increase Contrast`).
- **Subtle Duo paper-unfold play:** On a `closed → fullyOpen` hinge transition, the left rail map and frosted context card settle outward from the center crease with a staggered two-beat spring (`65ms` offset, subtle `-4.5° / -5.5°` hinge-edge perspective tilt, gentle scale settle, plus a single frosted ripple on the context card alone) while the right-hand feed stays anchored at its exact closed width. Disabled under `Reduce Motion`, `VoiceOver`, and `Increase Contrast`.
- **Zero idle burn:** Outside the active `0.60–0.62s` transition window, `TimelineView` pauses and `.layerEffect(..., isEnabled: false)` bypasses the shader completely.

## 5. Restraint & Accessibility Rules

- **No ASCII clipart:** Never use ASCII illustrations for categories, icons, pins, toggles, or progress bars; use native SF Symbols.
- **Clean launch screen:** Keep `UILaunchScreen` blank and native—zero splash art or ASCII on launch.
- **No permanent aberration:** Dispersion returns to `0` at rest so titles and body copy stay razor-sharp.
- **Accessibility first:**
  - The reticle and glass shader are marked `.accessibilityHidden(true)`.
  - When `accessibilityReduceMotion`, `accessibilityVoiceOverEnabled`, or `colorSchemeContrast == .increased` is active, ripples and refraction disable automatically and cards fall back to high-contrast static surfaces.
