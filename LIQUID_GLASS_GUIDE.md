# Liquid Glass Implementation Guide
# Reference for building native-feeling components in gemini-shortcut
# Edit this file as understanding grows.

---

## Core Principle: Glass Is a Material, Not a Animation

Apple's Liquid Glass is a *passive* material — it reacts to what's behind it (refraction, chromatism, blurring) automatically. You do NOT need to:
- Animate its border
- Rotate gradients over it
- Add manual specular highlights
- Overlay shimmer effects

The system does all of this. Your job is to NOT fight it.

---

## The Only Correct Way to Apply glassEffect in SwiftUI

```swift
// ✅ CORRECT — glassEffect is an instance method on Shape types only
RoundedRectangle(cornerRadius: 22, style: .continuous)
    .glassEffect(in: RoundedRectangle(cornerRadius: 22, style: .continuous))

Circle().glassEffect(in: Circle())

Capsule().glassEffect(in: Capsule())

// ✅ CORRECT — as a .background() modifier using a Shape
.background(
    RoundedRectangle(cornerRadius: 22, style: .continuous)
        .glassEffect(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
)

// ❌ WRONG — .background(.glassEffect(...)) — glassEffect is NOT a ShapeStyle
.background(.glassEffect(in: RoundedRectangle(cornerRadius: 22, style: .continuous)))

// ❌ WRONG — cannot call on a generic View (Button, Text, HStack, etc.)
Button { } label: { ... }
    .glassEffect(.regular.interactive(), in: Circle())  // compile error
```

---

## GlassEffectContainer — Merging Adjacent Controls

`GlassEffectContainer(spacing:)` is a real macOS 26 / iOS 26 SwiftUI type.
It groups adjacent glass views so they visually merge at their seams (the hallmark Liquid Glass grouped-control look).

```swift
// Model picker pills that merge into one fluid shape:
GlassEffectContainer(spacing: 0) {
    HStack(spacing: 0) {
        PillButton("Pro", isSelected: ...)
        PillButton("Flash Lite", isSelected: ...)
    }
}
```

Use `spacing: 0` for fully merged (no gap), `spacing: -1` for slight overlap/merge at boundary.
SourceKit may show "cannot find in scope" for this — that is a false positive. The build succeeds.

---

## NSPanel Setup for Floating Glass Panels

The panels use:
- `backgroundColor = .clear` — required for glass to composite against desktop
- `isOpaque = false` — required for transparency
- `hasShadow = true` — system shadow gives depth, don't add your own
- `level = .floating` — stays above normal windows
- `.borderless | .nonactivatingPanel | .fullSizeContentView` style mask

The glass effect composites against the actual desktop/wallpaper content.
This means: on a dark wallpaper, glass appears darker. On a light wallpaper, lighter.

**Consequence**: White-only text colors work on dark backgrounds but fail on light ones.
Use high-opacity white (0.85+) for primary text so it remains legible across backgrounds.
Consider adding `Color.black.opacity(0.15)` as the *first* ZStack layer for a minimum dark base.

---

## Animation Rules

### ✅ KEEP these animations:
- **Physical motion**: Panel open (spring up), panel close (drop + fade), resize
- **Spring physics on interactive elements**: Toggle thumb sliding (spring), message bubbles scaling in
- **Hover opacity**: Buttons/close button brightening on hover (0.1-0.15s easeInOut)
- **Focus state**: Input border brightening on focus (0.15s easeInOut)
- **Streaming text**: Text appending incrementally IS the animation — don't add extra effects
- **Entrance stagger**: Content vs. input bar staggered spring entrance (already correct)
- **LiquidOrb pulse**: Loading state indicator (physical pulsing = progress communication)

### ❌ REMOVE these animations:
- **Rotating/spinning border gradients** (`LiquidGlowOverlay` with `.linear(duration: 5).repeatForever`) — decorative, distracting, looks cheap
- **Counter-rotating overlays** — same
- Any `.repeatForever` animation that isn't communicating a loading/progress state

### Why:
Apple's HIG says animations must be *purposeful* — they should communicate state or guide attention.
A spinning border communicates nothing. It's decorative noise that competes with the glass material itself.

---

## Text Field Guidelines (from Apple HIG)

### Sizes:
- macOS native text field height: 22pt (compact), 28pt (regular), 32pt+ (custom)
- Padding: 8-14pt horizontal, 8-11pt vertical for touch-friendly sizing

### Placeholder text:
- Describes content type, not instructions: "API Key" not "Enter your API key here"
- Apple recommends 40-50% opacity for placeholder (white at 0.45-0.55 on dark glass)
- **Current code uses 0.38 — too dim. Bump to 0.50.**
- Do NOT use placeholder as the sole label (Apple HIG violation), but in a minimalist UI it's acceptable

### Focus state:
- macOS: system blue ring (3px). In custom glass: bright border stroke (white at 0.45 opacity, 1.5px) is the right analog.
- The focus border should appear/disappear with a quick ease (0.12-0.15s) — already correct.

### Return key:
- Should trigger primary action (send, save) — already correct in ContentView.

### Escape key:
- Should dismiss/cancel — already handled in AppDelegate.

---

## Button Guidelines (from Apple HIG)

### Minimum hit targets:
- macOS: 22pt height minimum; 28-32pt preferred for click comfort
- iOS: 44×44pt minimum (not relevant here)
- Current close button: 20×20 — slightly under. Should be 24×24 minimum.
- Current send button: 26×26 — acceptable.

### Button types in this app:
- **Primary action** (Send): Accent color fill when active, glass when disabled — ✅ correct
- **Secondary/ghost** (Camera, Close): Plain style with glass background — ✅ correct
- **Segmented** (Model picker): Glass pills in GlassEffectContainer — ✅ correct
- **Form action** (Save): Full-width glass button — ✅ correct

### States:
- Default: glass background, 0.9 opacity text
- Hover: glass + opacity bump to 1.0, 0.12-0.15s ease — ✅ already implemented
- Pressed: system handles press-state darkening with glass material
- Disabled: 0.3 opacity text, 0.5 opacity background — ✅ correct

### Key rule:
DO NOT animate `.glassEffect()` itself. Animate the content (opacity, scale, offset) inside/around it.

---

## Toggle Guidelines (from Apple HIG)

### Usage:
- Binary on/off settings that take effect *immediately*
- Label describes the "on" state: "Enable tool calling" (what happens when ON) — ✅ correct
- Don't use toggles for actions that require confirmation

### The GlassToggle implementation is correct:
- Spring animation on state change (physical motion) — ✅
- Thumb slides (spring response: 0.28, damping: 0.68) — natural feel
- Track gets accent tint overlay when on — ✅
- Glass capsule track — ✅

**Don't change the toggle — it's working correctly.**

---

## Progress Indicators (from Apple HIG)

### Types:
- **Indeterminate spinner**: Duration unknown (SwiftUI `ProgressView()`) — use for API calls
- **Determinate progress bar**: Duration/percentage known — not applicable here
- **Custom pulsing**: LiquidOrb is the thinking indicator while a response is starting

### Current app uses:
- `ProgressView()` during streaming — renders system spinner — ✅ correct
- `LiquidOrb` while waiting for first token (showThinkingIndicator) — ✅ correct
- Streaming text appearing incrementally — this IS the progress indicator for the response

**Keep LiquidOrb pulse animation — it communicates loading state (purposeful).**
**Keep ProgressView() — system-appropriate.**

---

## Material Layering Rules

### Correct layering (bottom to top):
1. Desktop/wallpaper (composited by system through `backgroundColor = .clear`)
2. `Color.black.opacity(0.12-0.18)` — minimum dark base for text legibility (optional but recommended)
3. `LiquidGlassContainer` (`.glassEffect()` on RoundedRectangle) — the main glass surface
4. Content (text, icons, controls) — should be white-tinted for glass aesthetic
5. ~~`LiquidGlowOverlay`~~ — REMOVE. The glass handles its own edge definition.

### Don't layer glass on glass:
- Each control (input bar, message bubble, toggle) already applies its own `.glassEffect()`
- The outer panel also has `.glassEffect()`
- This creates nested glass surfaces which is intentional and correct
- Do NOT add extra glass layers beyond what exists

### Edge definition:
- The native glass effect provides a subtle edge/border automatically
- Adding a manual stroke on top of glass is acceptable for focus states (thin, bright)
- Do NOT add thick or animated strokes — they fight the material

---

## Contrast Checklist

For the floating panel on ANY background:
- Primary text: `Color.white.opacity(0.92)` or higher — ✅
- Secondary text / labels: `Color.white.opacity(0.80)` minimum (current settings labels at 0.9 — ✅)
- Placeholder text: `Color.white.opacity(0.50)` minimum (**current: 0.38 — NEEDS FIX**)
- Disabled text: `Color.white.opacity(0.30)` — acceptable for clearly disabled state
- Model message fill: `Color.white.opacity(0.12)` minimum (**current: 0.06 — too subtle, NEEDS FIX**)
- Model message stroke: `Color.white.opacity(0.20)` minimum (**current: 0.10 — too subtle, NEEDS FIX**)

---

## What Makes a Component Feel "Usable"

1. **It's clearly interactive**: hit targets ≥28×28pt, visible affordance on hover
2. **Text is readable**: contrast ratio sufficient against glass background
3. **State is communicated clearly**: focus rings, selection indicators, disabled states all visible
4. **Feedback is immediate**: hover → 0.1-0.15s response; tap → spring (instant-feeling)
5. **It doesn't fight the background**: no spinning decorations, let glass do its job

---

## Known Working Patterns in This Codebase

```swift
// Panel-level glass background (ContentView / SettingsView ZStack):
LiquidGlassContainer(cornerRadius: 28)
// ← Remove LiquidGlowOverlay from here

// Input bar glass:
RoundedRectangle(cornerRadius: 22, style: .continuous)
    .glassEffect(in: RoundedRectangle(cornerRadius: 22, style: .continuous))

// Small interactive glass (close button, send when empty):
Circle().glassEffect(in: Circle())

// Toggle track:
Capsule().glassEffect(in: Capsule())

// Text field glass:
RoundedRectangle(cornerRadius: 22, style: .continuous)
    .glassEffect(in: RoundedRectangle(cornerRadius: 22, style: .continuous))

// Merged control group (model picker):
GlassEffectContainer(spacing: 0) { ... }

// Active send button (non-glass):
Circle().fill(Color.accentColor)
```

---

## Streaming Text Animation

The response streams in token by token via `AsyncStream<String>`.
- `ChatViewModel.messages` last item gets text appended
- SwiftUI's `Text(message.text)` re-renders automatically
- This IS the animation — each new character/word appearing IS motion
- Do NOT add fade/scale transitions to the streaming text itself (it will stutter)
- DO keep the `LiquidOrb` thinking indicator that shows before the first token arrives

---

## TODO / Things to Revisit

- [ ] Close button hit target: 20×20 → 24×24
- [ ] Placeholder opacity: 0.38 → 0.50 in RevealBlurTextField and GlassTextEditor
- [ ] Model message bubble contrast: fill 0.06→0.12, stroke 0.10→0.20
- [ ] Remove LiquidGlowOverlay from ContentView and SettingsView
- [ ] Consider adding `Color.black.opacity(0.12)` base layer in panel ZStacks for light-background legibility
- [ ] Verify GlassEffectContainer compiles correctly in SettingsView (SourceKit false positives expected)
