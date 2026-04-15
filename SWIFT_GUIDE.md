# Swift & SwiftUI Guide for Gemini Shortcut

This guide explains how the project's UI is structured and how you can customize its components.

## How Swift Works in This Project

This app is built using **SwiftUI**, Apple's modern framework for building user interfaces. Instead of imperative code (e.g., "add a button here"), you use **declarative code** (e.g., "there is a button with this look").

### 1. Views and Components
Every UI element is a `View`. You can find them in `gemini-shortcut/`.
- `ContentView.swift`: The main chat interface.
- `SettingsView.swift`: The settings panel shown in your screenshot.
- `GlassUI.swift`: This is where all the custom "Liquid Glass" components are defined.

### 2. The "Liquid Glass" Effect
We use the native `.glassEffect()` modifier (available in the latest macOS). 
- **Refraction:** It blurs and distorts what's behind it, like real glass.
- **Chromatic Aberration:** It adds subtle color fringing at the edges.
- **Tinting:** We can "dye" the glass by adding a `.tint()` to the effect.

---

## Changing the Components

### Reducing Background Darkness
If the UI is too dark, it's usually because the `LiquidGlassContainer` is picking up dark colors from the desktop or the system theme. To fix this, we can add a light tint to the glass.

**Where to find it:** `gemini-shortcut/GlassUI.swift`
**Look for:** `LiquidGlassContainer`

**How to change it:**
Change the `glassEffect` to include a white tint:
```swift
.glassEffect(.regular.tint(Color.white.opacity(0.2)), in: ...)
```

### How Glass is Applied
You asked if we put the effect on the component or in the background. In this project, we do both depending on the need:

1.  **On the Component (Directly):** 
    Used for buttons and small items. The glass *is* the button's shape.
    ```swift
    Text("Button")
        .glassEffect(...) // The text sits on top of its own glass background
    ```
2.  **In the Background (ZStack):** 
    Used for containers or complex toggles. We place a glass layer *behind* everything else.
    ```swift
    ZStack {
        LiquidGlassContainer() // The background glass
        VStack { ... content ... }
    }
    ```

### Modifying Toggles & Buttons
- **Toggles:** Find `GlassToggle` in `GlassUI.swift`. You can change the `accentColor` or the thumb size.
- **Buttons:** Find `GlassPillButton` or `GlassButton`. You can change the `padding` for size or the `opacity` for transparency.

---

## Pro-Tips for Editing
- **Colors:** Use `Color.white.opacity(0.5)` for semi-transparent white.
- **Padding:** Change `.padding(10)` to a larger number to give elements more "breathing room."
- **Rounding:** Change `cornerRadius: 24` to `cornerRadius: 12` if you want a more "square" look.
