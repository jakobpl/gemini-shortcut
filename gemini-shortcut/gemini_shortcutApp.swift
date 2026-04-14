//
//  gemini_shortcutApp.swift
//  gemini-shortcut
//
//  Created by jakob n on 4/14/26.
//

import SwiftUI
import AppKit

@main
struct gemini_shortcutApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
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
    
    func applicationDidFinishLaunching(_ notification: Notification) {
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
    }
    
    // MARK: - Main Shortcut Panel
    
    func setupPanel() {
        let contentRect = NSRect(x: 0, y: 0, width: 620, height: 70)
        let panel = NSPanel(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: ContentView())
        
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - contentRect.width / 2
            let y = screenFrame.minY + 100
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
        
        self.panel = panel
    }
    
    // MARK: - Settings Panel
    
    func setupSettingsPanel() {
        let contentRect = NSRect(x: 0, y: 0, width: 380, height: 420)
        let panel = NSPanel(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: SettingsView(dismiss: { [weak self] in
            self?.hideSettingsPanel()
        }))
        
        self.settingsPanel = panel
    }
    
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
        
        // Hide main panel if open
        hidePanel()
        
        if let button = statusItem?.button, let screen = NSScreen.main {
            let buttonFrame = button.window?.convertToScreen(button.frame) ?? button.frame
            let panelHeight: CGFloat = 420
            let panelWidth: CGFloat = 380
            let x = buttonFrame.midX - panelWidth / 2
            let y = screen.visibleFrame.maxY - buttonFrame.height - panelHeight + 8
            
            let finalRect = NSRect(x: x, y: y, width: panelWidth, height: panelHeight)
            let startRect = NSRect(x: finalRect.midX - 10, y: finalRect.origin.y + 10, width: 20, height: 20)
            
            settingsPanel.setFrame(startRect, display: false)
            settingsPanel.alphaValue = 0
            settingsPanel.makeKeyAndOrderFront(nil)
            
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                settingsPanel.animator().setFrame(finalRect, display: true)
                settingsPanel.animator().alphaValue = 1
            }
        } else {
            settingsPanel.makeKeyAndOrderFront(nil)
        }
    }
    
    func hideSettingsPanel() {
        guard let settingsPanel = settingsPanel, settingsPanel.isVisible else { return }
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            settingsPanel.animator().alphaValue = 0
        } completionHandler: {
            settingsPanel.orderOut(nil)
            settingsPanel.alphaValue = 1
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
    
    @objc func handleResizeNotification(_ notification: Notification) {
        guard let height = notification.object as? CGFloat, let panel = panel, let screen = NSScreen.main else { return }
        
        let currentFrame = panel.frame
        let newFrame = NSRect(
            x: screen.visibleFrame.midX - currentFrame.width / 2,
            y: screen.visibleFrame.minY + 100,
            width: currentFrame.width,
            height: height
        )
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(newFrame, display: true)
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
    
    // MARK: - Show / Hide Main Panel
    
    func showPanel() {
        guard let panel = panel else { return }
        
        NSApp.activate(ignoringOtherApps: true)
        hideSettingsPanel()
        
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let finalRect = NSRect(
                x: screenFrame.midX - panel.frame.width / 2,
                y: screenFrame.minY + 100,
                width: panel.frame.width,
                height: panel.frame.height
            )
            let startRect = NSRect(
                x: finalRect.origin.x,
                y: finalRect.origin.y - 30,
                width: finalRect.width,
                height: finalRect.height
            )
            
            panel.setFrame(startRect, display: false)
            panel.alphaValue = 0
            panel.makeKeyAndOrderFront(nil)
            
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(finalRect, display: true)
                panel.animator().alphaValue = 1
            }
        } else {
            panel.makeKeyAndOrderFront(nil)
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
        
        if let screen = NSScreen.main {
            let compactRect = NSRect(
                x: screen.visibleFrame.midX - panel.frame.width / 2,
                y: screen.visibleFrame.minY + 100,
                width: panel.frame.width,
                height: 70
            )
            panel.setFrame(compactRect, display: true)
        }
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = 0
        } completionHandler: {
            panel.orderOut(nil)
            panel.alphaValue = 1
        }
    }
    
    func windowDidResignKey(_ notification: Notification) {
        if let window = notification.object as? NSWindow {
            if window === panel {
                hidePanel()
            } else if window === settingsPanel {
                hideSettingsPanel()
            }
        }
    }
}
