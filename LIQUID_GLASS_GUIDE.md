# Liquid Glass Implementation Guide

## Core Principle

Apple's Liquid Glass is a *passive* material — it reacts to what's behind it automatically. Do NOT animate its border, rotate gradients, or add manual specular highlights.

## Correct glassEffect Usage

```swift
// ✅ CORRECT — glassEffect is an instance method on ANY View
Text("Hello")
    .padding()
    .glassEffect(.regular.tint(Color.white.opacity(0.15)).interactive(), in: .rect(cornerRadius: 22, style: .continuous))

// ❌ WRONG — Using a Shape as a background without .fill(.clear)
.background(
    Circle() // Draws solid by default!
        .glassEffect(.regular.tint(Color.white.opacity(0.15)).interactive(), in: .circle)
)
```

## NSPanel Setup for Floating Glass Panels

- `backgroundColor = .clear`
- `isOpaque = false`
- `hasShadow = true`
- `level = .floating`
- `styleMask = [.borderless, .nonactivatingPanel, .fullSizeContentView, .resizable]`

## Animation Rules

### ✅ KEEP
- Physical motion: panel open/close, resize
- Spring physics on toggles and buttons
- Hover opacity (0.1–0.15s easeInOut)
- Focus border brightening (0.12–0.15s)
- Streaming text appearing incrementally

### ❌ REMOVE
- Rotating border gradients
- Counter-rotating overlays
- Any `.repeatForever` that isn't loading/progress

## Button Guidelines

- Minimum hit target: 28×28pt
- `.menuStyle(.borderlessButton)` + `.fixedSize()` for dropdowns in glass capsules
- Do NOT wrap Menu label in `.glassEffect()` — the parent already provides it

## Material Layering (bottom to top)

1. Desktop/wallpaper
2. `Color.black.opacity(0.12–0.18)` — minimum dark base for text legibility
3. `.glassEffect()` — main glass surface
4. Content (white-tinted text and controls)

## Contrast Checklist

- Primary text: `Color.white.opacity(0.92)`
- Secondary text: `Color.white.opacity(0.80)` minimum
- Placeholder: `Color.white.opacity(0.50)` minimum
- Model message fill: add `Color.black.opacity(0.28)` behind glass for light-background legibility

## References

- https://developer.apple.com/design/human-interface-guidelines/materials
- https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views
