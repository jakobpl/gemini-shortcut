# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**gemini-shortcut** is a macOS menu bar application that provides quick access to Google's Gemini API through a floating panel interface. The app activates via double-tapping the Command key and features a glassmorphic UI design.

## Build & Run

This is a native macOS SwiftUI app built with Xcode.

**Build the app:**
```bash
xcodebuild -project gemini-shortcut.xcodeproj -scheme gemini-shortcut -configuration Debug build
```

**Open in Xcode:**
```bash
open gemini-shortcut.xcodeproj
```

**Run from Xcode:** Use Cmd+R or select Product > Run

**Note:** The app requires macOS 26.2+ and uses the development team ID `R96Q6JG8Q7`. App sandboxing is disabled (`ENABLE_APP_SANDBOX = NO`) to allow screen capture and terminal command execution.

## Architecture

### Panel System
The app uses two independent `NSPanel` instances managed by `AppDelegate`:
- **Main Panel** (`panel`): Chat interface that appears on Command double-tap
- **Settings Panel** (`settingsPanel`): Configuration UI triggered by clicking the menu bar icon

Both panels use the same glassmorphic design pattern and animate in/out with spring physics.

### Activation Flow
1. User double-taps Command key (within 0.3s interval)
2. `AppDelegate.handleFlagsChanged()` detects the gesture via `NSEvent.addGlobalMonitorForEvents`
3. `showPanel()` animates the main panel from bottom with fade-in
4. Panel auto-dismisses on outside click or Escape key

### Chat Architecture
The chat system uses streaming responses:
- `ChatViewModel` manages conversation state and user input
- `GeminiAPI.streamResponse()` returns an `AsyncStream<String>` that yields text chunks
- Messages are appended incrementally to the last message in the array
- The UI observes `@Published` properties and updates in real-time

### Message Windowing
To manage context limits, `GeminiAPI` implements a 6-message sliding window:
- If conversation has ≤6 meaningful messages, send all
- If >6 messages, summarize older messages as a single system message
- Always include the most recent 6 messages with full content

### Tool Calling
When enabled, the app supports Gemini's function calling API:
- `run_terminal_command`: Executes bash commands via `Process` and returns output
- Tool responses are injected back into the message stream with formatted code blocks

### Settings Persistence
- **API Key**: Stored in macOS Keychain via `Security.framework`
- **Other settings**: Stored in `UserDefaults` (model selection, custom instructions, feature flags)
- **Dev Mode**: Setting API key to "dev" bypasses the real API and returns mock streaming responses

### UI Components
All custom UI components are in `GlassUI.swift`:
- `LiquidGlassContainer`: Layered `NSVisualEffectView` with popover + hudWindow materials
- `LiquidGlowOverlay`: Animated rotating gradient border
- `LiquidOrb`: Pulsing thinking indicator
- `RevealBlurTextField`: API key field that blurs when not focused
- `GlassTextEditor`, `GlassToggle`, `GlassPillButton`, `GlassButton`: Themed form controls

**Note:** `GlassIconButton` is referenced in `SettingsView.swift` but not yet implemented.

### Screenshot Integration
`ScreenshotService` uses `ScreenCaptureKit` to capture the primary display:
- Captures entire screen as `NSImage`
- Converts to PNG data via `NSBitmapImageRep`
- Encodes as base64 for Gemini's `inlineData` format
- Screenshots are attached to messages and sent with the API request

### Dynamic Panel Resizing
The panel height dynamically adjusts based on content:
- Default compact height: 70pt
- Expanded with messages: 480pt
- `ContentView` posts `NSNotification` with target height
- `AppDelegate` animates the panel frame change with spring timing

## Available Gemini Models

The app supports:
- `gemini-3.1-pro-preview` (default)
- `gemini-3.1-flash-lite-preview`

## Key Files

- `gemini_shortcutApp.swift`: App entry point and `AppDelegate` with panel management
- `ContentView.swift`: Main chat UI with message list and input controls
- `GeminiAPI.swift`: API client with streaming and tool calling support
- `ChatViewModel.swift`: Chat state management and send logic
- `SettingsView.swift`: Settings panel UI
- `SettingsManager.swift`: Settings persistence layer (Keychain + UserDefaults)
- `GlassUI.swift`: Reusable glassmorphic UI components
- `ScreenshotService.swift`: Screen capture via ScreenCaptureKit
- `ChatMessage.swift`: Message model with role, text, image, and streaming state

## Entitlements

The app requires the following capabilities (see `gemini-shortcut.entitlements`):
- Screen recording permission for screenshot capture
- Network access for Gemini API calls
- Unrestricted file access (`ENABLE_USER_SELECTED_FILES = readonly` is set but sandbox is disabled)
