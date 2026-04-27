import AppKit
import ApplicationServices

enum SelectionCapture {
    /// Attempts to return the currently selected text in the frontmost app.
    /// Tries Accessibility API first, falls back to clipboard synthesis.
    static func currentFrontmostSelection() -> String? {
        if let axText = axSelectedText(), !axText.isEmpty {
            return axText
        }
        return fallbackClipboardSelection()
    }

    // MARK: - Accessibility API

    private static func axSelectedText() -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedElement: CFTypeRef?
        let focusResult = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        guard focusResult == .success, let element = focusedElement else { return nil }

        var selectedText: CFTypeRef?
        let textResult = AXUIElementCopyAttributeValue(element as! AXUIElement, kAXSelectedTextAttribute as CFString, &selectedText)
        guard textResult == .success, let text = selectedText as? String else { return nil }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Clipboard Fallback

    private static func fallbackClipboardSelection() -> String? {
        let pasteboard = NSPasteboard.general
        let previous = pasteboard.string(forType: .string)

        // Synthesize Cmd+C
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: true) // kVK_ANSI_C
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: false)
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)

        // Give the target app a moment to populate the pasteboard
        Thread.sleep(forTimeInterval: 0.08)

        let captured = pasteboard.string(forType: .string)

        // Restore previous clipboard contents
        if let previous {
            pasteboard.clearContents()
            pasteboard.setString(previous, forType: .string)
        }

        guard let captured, !captured.isEmpty else { return nil }
        return captured.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
