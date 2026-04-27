import SwiftUI
import AppKit

@main
struct voidApp: App {
    let controller = PanelController()

    init() {
        controller.setup()
    }

    var body: some Scene {
        Settings { EmptyView() }
    }
}

// MARK: - KeyablePanel

class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: - PanelController

final class PanelController: NSObject, NSWindowDelegate {
    var panel: NSPanel?
    var settingsPanel: NSPanel?
    var statusItem: NSStatusItem?

    private var lastCommandRelease: Date?
    private var isCommandDown = false
    private let doubleTapInterval: TimeInterval = 0.3
    private var flagsMonitor: Any?
    private var localFlagsMonitor: Any?
    private var escapeMonitor: Any?
    private var clickMonitor: Any?

    private let panelOriginKey = "gemini-panel-origin"

    func setup() {
        setupPanel()
        setupSettingsPanel()
        setupStatusBar()
        setupMonitors()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleResizeNotification(_:)),
            name: .geminiResizePanel,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleClosePanelNotification),
            name: .geminiClosePanel,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePreviewPositionNotification),
            name: .geminiPreviewPosition,
            object: nil
        )
    }

    // MARK: - Main Chat Panel

    func setupPanel() {
        let contentRect = NSRect(x: 0, y: 0, width: 580, height: 70)
        let panel = KeyablePanel(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView, .resizable],
            backing: .buffered,
            defer: false
        )

        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.delegate = self

        let hostingView = NSHostingView(rootView: ContentView())
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = CGColor.clear
        panel.contentView = hostingView

        if let screen = NSScreen.main {
            let sf = screen.visibleFrame
            let savedOrigin = getSavedPanelOrigin()
            let x: CGFloat
            let y: CGFloat

            if let saved = savedOrigin {
                x = saved.x
                y = saved.y
            } else {
                x = sf.midX - contentRect.width / 2
                y = sf.minY + 100
            }

            let clampedX = max(sf.minX, min(x, sf.maxX - contentRect.width))
            let clampedY = max(sf.minY, min(y, sf.maxY))
            panel.setFrameOrigin(NSPoint(x: clampedX, y: clampedY))
        }

        self.panel = panel
    }

    // MARK: - Settings Panel

    func setupSettingsPanel() {
        let contentRect = NSRect(x: 0, y: 0, width: 360, height: 330)
        let panel = KeyablePanel(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView, .resizable],
            backing: .buffered,
            defer: false
        )

        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.delegate = self

        let hostingView = NSHostingView(rootView: SettingsView(dismiss: { [weak self] in
            self?.hideSettingsPanel()
        }))
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = CGColor.clear
        panel.contentView = hostingView

        self.settingsPanel = panel
    }

    // MARK: - Status Bar

    func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Gemini Shortcut")
            button.action = #selector(statusBarClicked(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    @objc func statusBarClicked(_ sender: NSStatusBarButton) {
        guard let settingsPanel = settingsPanel else { return }

        if settingsPanel.isVisible {
            hideSettingsPanel()
            return
        }

        hidePanel()
        NSApp.activate(ignoringOtherApps: true)

        if let button = statusItem?.button, let screen = NSScreen.main {
            let buttonFrame = button.window?.convertToScreen(button.frame) ?? button.frame
            let panelWidth: CGFloat = 360
            let panelHeight: CGFloat = 330
            let x = buttonFrame.midX - panelWidth / 2
            let y = screen.visibleFrame.maxY - buttonFrame.height - panelHeight + 8

            let finalRect = NSRect(x: x, y: y, width: panelWidth, height: panelHeight)
            let startRect = NSRect(x: finalRect.midX - 8, y: finalRect.midY - 8, width: 16, height: 16)

            settingsPanel.setFrame(startRect, display: false)
            settingsPanel.alphaValue = 0
            settingsPanel.makeKeyAndOrderFront(nil)

            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.28
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1.0, 0.36, 1.0)
                settingsPanel.animator().setFrame(finalRect, display: true)
                settingsPanel.animator().alphaValue = 1
            }
        } else {
            settingsPanel.makeKeyAndOrderFront(nil)
        }
    }

    func hideSettingsPanel() {
        guard let settingsPanel = settingsPanel, settingsPanel.isVisible else { return }

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.16
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            settingsPanel.animator().alphaValue = 0
        } completionHandler: {
            settingsPanel.orderOut(nil)
            settingsPanel.alphaValue = 1
        }
    }

    // MARK: - Show / Hide Chat Panel

    func showPanel() {
        guard let panel = panel else { return }

        NSApp.activate(ignoringOtherApps: true)
        hideSettingsPanel()

        if let screen = panel.screen ?? NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main {
            let sf = screen.visibleFrame
            let savedOrigin = getSavedPanelOrigin()
            let originX: CGFloat
            let originY: CGFloat

            if let saved = savedOrigin {
                originX = max(sf.minX, min(saved.x, sf.maxX - panel.frame.width))
                originY = max(sf.minY, min(saved.y, sf.maxY))
            } else {
                originX = sf.midX - panel.frame.width / 2
                originY = sf.minY + 100
            }

            let finalRect = NSRect(
                x: originX,
                y: originY,
                width: panel.frame.width,
                height: panel.frame.height
            )
            let startRect = NSRect(
                x: finalRect.origin.x,
                y: finalRect.origin.y - 28,
                width: finalRect.width,
                height: finalRect.height
            )

            panel.setFrame(startRect, display: false)
            panel.alphaValue = 0
            panel.makeKeyAndOrderFront(nil)

            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.32
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1.0, 0.36, 1.0)
                panel.animator().setFrame(finalRect, display: true)
                panel.animator().alphaValue = 1
            } completionHandler: {
                NotificationCenter.default.post(name: .geminiPanelDidShow, object: nil)
            }
        } else {
            panel.makeKeyAndOrderFront(nil)
            NotificationCenter.default.post(name: .geminiPanelDidShow, object: nil)
        }

        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.hidePanel()
        }
    }

    func hidePanel() {
        guard let panel = panel, panel.isVisible else { return }

        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }

        savePanelOrigin(panel.frame.origin)

        let targetRect = NSRect(
            x: panel.frame.origin.x,
            y: panel.frame.origin.y - 14,
            width: panel.frame.width,
            height: panel.frame.height
        )

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(targetRect, display: true)
            panel.animator().alphaValue = 0
        } completionHandler: {
            panel.orderOut(nil)
            panel.alphaValue = 1
            if let screen = panel.screen ?? NSScreen.main {
                let origin = self.getSavedPanelOrigin() ?? NSPoint(x: screen.visibleFrame.midX - panel.frame.width / 2,
                                                                   y: screen.visibleFrame.minY + 100)
                let compactRect = NSRect(
                    x: origin.x,
                    y: origin.y,
                    width: panel.frame.width,
                    height: 70
                )
                panel.setFrame(compactRect, display: false)
            }
        }
    }

    // MARK: - Monitors

    func setupMonitors() {
        flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
        }
        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
            return event
        }
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.hidePanel()
                self?.hideSettingsPanel()
            }
            return event
        }
    }

    func handleFlagsChanged(_ event: NSEvent) {
        let commandMask: NSEvent.ModifierFlags = .command
        let currentlyDown = event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(commandMask)

        if currentlyDown && !isCommandDown {
            let now = Date()
            if let last = lastCommandRelease, now.timeIntervalSince(last) < doubleTapInterval {
                showPanel()
                lastCommandRelease = nil
            } else {
                isCommandDown = true
            }
        } else if !currentlyDown && isCommandDown {
            lastCommandRelease = Date()
            isCommandDown = false
        }
    }

    @objc func handleResizeNotification(_ notification: Notification) {
        guard let height = notification.object as? CGFloat,
              let panel = panel,
              panel.screen ?? NSScreen.main != nil else { return }

        let currentFrame = panel.frame
        let currentOrigin = currentFrame.origin
        let heightDelta = height - currentFrame.height
        let newY = currentOrigin.y - heightDelta

        let newFrame = NSRect(
            x: currentOrigin.x,
            y: newY,
            width: currentFrame.width,
            height: height
        )

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.28
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1.0, 0.36, 1.0)
            panel.animator().setFrame(newFrame, display: true)
        }
    }

    @objc func handleClosePanelNotification() {
        hidePanel()
    }

    @objc func handlePreviewPositionNotification() {
        hidePanel()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.showPanel()
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        if let window = notification.object as? NSWindow {
            if window === panel { hidePanel() }
            else if window === settingsPanel { hideSettingsPanel() }
        }
    }

    // MARK: - Panel Position Persistence

    private func savePanelOrigin(_ origin: NSPoint) {
        UserDefaults.standard.set([origin.x, origin.y], forKey: panelOriginKey)
    }

    private func getSavedPanelOrigin() -> NSPoint? {
        guard let saved = UserDefaults.standard.array(forKey: panelOriginKey) as? [CGFloat],
              saved.count == 2 else { return nil }
        return NSPoint(x: saved[0], y: saved[1])
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let geminiResizePanel  = Notification.Name("GeminiResizePanel")
    static let geminiClosePanel   = Notification.Name("GeminiClosePanel")
    static let geminiPanelDidShow = Notification.Name("GeminiPanelDidShow")
    static let geminiInjectText   = Notification.Name("GeminiInjectText")
    static let geminiPreviewPosition = Notification.Name("GeminiPreviewPosition")
}
