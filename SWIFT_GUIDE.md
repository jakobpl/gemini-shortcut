# Swift & SwiftUI Quick Reference

## Glass Effect Patterns

Apply `.glassEffect()` directly on the view, not in a `.background()`:

```swift
Text("Hello")
    .padding()
    .glassEffect(.regular.tint(Color.white.opacity(0.15)).interactive(), in: .rect(cornerRadius: 22, style: .continuous))
```

For containers, use a `ZStack` with the glass layer behind content:

```swift
ZStack {
    Color.clear
        .glassEffect(.regular.tint(Color.white.opacity(0.15)).interactive(), in: .rect(cornerRadius: 28, style: .continuous))
    // content
}
```

## Colors & Opacity

- Primary text: `Color.white.opacity(0.92)`
- Secondary text: `Color.white.opacity(0.80)`
- Placeholder: `Color.white.opacity(0.50)`
- Disabled: `Color.white.opacity(0.30)`

## Common Modifiers

- `.clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))`
- `.textSelection(.enabled)` for copyable text
- `.buttonStyle(.plain)` for custom glass buttons
