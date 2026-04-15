#see the following documentation
https://developer.apple.com/design/human-interface-guidelines/text-fields
https://developer.apple.com/design/human-interface-guidelines/toggles
https://developer.apple.com/design/human-interface-guidelines/progress-indicators
https://developer.apple.com/design/human-interface-guidelines/menus-and-actions
https://developer.apple.com/design/human-interface-guidelines/materials
https://developer.apple.com/design/human-interface-guidelines/buttons
https://developer.apple.com/design/human-interface-guidelines/search-fields
https://developer.apple.com/design/human-interface-guidelines/keyboards
https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views


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
// ✅ CORRECT — glassEffect is an instance method on ANY View. You must provide the bounding shape.
Text("Hello")
    .padding()
    .glassEffect(.regular.tint(Color.white.opacity(0.15)).interactive(), in: .rect(cornerRadius: 22, style: .continuous))
    

Image(systemName: "xmark")
    .padding()
    .glassEffect(.regular.tint(Color.white.opacity(0.15)).interactive(), in: .circle)
    

// ❌ WRONG — Using a Shape as a background without .fill(.clear)
// This creates a solid filled shape using the inherited foreground color. The glass effect
// then overlays this solid color, which gives it nothing to "refract". This is the primary
// reason liquid glass icons end up looking like muddy "grey backdrops"!
.background(
    Circle() // Draws as solid black/white by default!
        .glassEffect(.regular.tint(Color.white.opacity(0.15)).interactive(), in: .circle)
)

// ❌ WRONG — Putting it in a background instead of directly on the View
.background(
    Color.clear
        .glassEffect(.regular.tint(Color.white.opacity(0.15)).interactive(), in: .circle)
)

// ❌ WRONG — .background(.glassEffect(...)) — glassEffect is NOT a ShapeStyle
.background(.glassEffect(.regular.tint(Color.white.opacity(0.15)).interactive(), in: .rect(cornerRadius: 22)))
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
- **Current code uses 0.50 — matches HIG.**
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
- Current close button: 28×28 — optimal.
- Current send button: 32×32 — optimal.
- Current camera button: 32×32 — optimal.

### Button types in this app:
- **Primary action** (Send): Accent color fill when active, ghost when disabled — ✅ correct
- **Secondary/ghost** (Close): Plain style with glass background — ✅ correct
- **Menu button** (Attach "+"): SwiftUI `Menu` with `.menuStyle(.borderlessButton)` + `.fixedSize()` — see below
- **Pill toggle** (Model): Single glass capsule in the input bar; tapping cycles Pro ↔ Flash — ✅ correct
- **Form action**: Full-width glass button — ✅ correct

### States:
- Default: glass background, 0.9 opacity text
- Hover: glass + opacity bump to 1.0, 0.12-0.15s ease — ✅ already implemented
- Pressed: system handles press-state darkening with glass material
- Disabled: 0.3 opacity text, 0.5 opacity background — ✅ correct

### Key rule:
DO NOT animate `.glassEffect()` itself. Animate the content (opacity, scale, offset) inside/around it.

---

## Menu Button Pattern (Dropdown in Input Bar)

The "+" attach button uses SwiftUI's `Menu` instead of a plain `Button` so it can show
a native dropdown without any extra gesture recognition:

```swift
Menu {
    Button("Take Screenshot") { viewModel.attachScreenshot() }
    Button("Attach File…")    { viewModel.attachFile() }
} label: {
    Image(systemName: "plus")
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(Color.white.opacity(0.75))
        .frame(width: 30, height: 30)
}
.menuStyle(.borderlessButton)   // strips the default bordered button chrome
.fixedSize()                    // prevents the Menu from expanding to fill HStack
```

**Key rules:**
- Always `.menuStyle(.borderlessButton)` inside a glass capsule — the default bordered style fights the glass
- Always `.fixedSize()` — without it the Menu stretches to fill available space
- Do NOT wrap the label image in `.glassEffect()` — the parent capsule already provides the glass surface

---

## Model Selection — Chat Pill Only

Model selection lives exclusively in the chat input bar pill (ContentView).
The settings panel does **not** have a model picker.

Why: the model is a per-conversation choice that benefits from quick in-context switching,
not a global app preference buried in settings.

The pill writes to `@AppStorage("gemini-selected-model")`.
`GeminiAPI.streamResponse` reads `SettingsManager.shared.selectedModel` which reads the same
`UserDefaults` key — so the two stay in sync without any notification bus.

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
Color.clear
    .glassEffect(.regular.tint(Color.white.opacity(0.15)).interactive(), in: .rect(cornerRadius: 28, style: .continuous))
    

// Input bar glass:
.glassEffect(.regular.tint(Color.white.opacity(0.15)).interactive(), in: .rect(cornerRadius: 22, style: .continuous))


// Small interactive glass (close button, send when empty):
.glassEffect(.regular.tint(Color.white.opacity(0.15)).interactive(), in: .circle)


// Toggle track:
Color.clear
    .frame(width: 48, height: 26)
    .glassEffect(.regular.tint(Color.white.opacity(0.15)).interactive(), in: .capsule)
    

// Text field glass:
.glassEffect(.regular.tint(Color.white.opacity(0.15)).interactive(), in: .rect(cornerRadius: 22, style: .continuous))


// Merged control group (model picker):
GlassEffectContainer(spacing: 0) { ... }

// Active send button (non-glass):
.background(Circle().fill(Color.accentColor))
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

- [x] Close button hit target: 20×20 → 28×28 (exceeds 24x24 minimum)
- [x] Placeholder opacity: 0.38 → 0.50 in RevealBlurTextField and GlassTextEditor
- [x] Model message bubble contrast: fill 0.12, stroke 0.20 (verified)
- [x] Remove LiquidGlowOverlay from guides (already gone from code)
- [x] Add `Color.black.opacity(0.12)` base layer in panel ZStacks for light-background legibility
- [x] Update interactive buttons (Send, Camera, Close) to use 28x28 or 32x32 hit targets.
- [x] Refined GlassEffectContainer: Children SHOULD use their own .glassEffect() for the "morphing" look.
- [x] All primary buttons now use .bold weight and higher opacities.
- [x] Remove model picker from SettingsView — model lives in chat input pill only.
- [x] Replace "+" screenshot shortcut with a Menu dropdown (Take Screenshot / Attach File).
- [x] Add code comments to all UI components documenting what triggers them.
