//
//  ScreenshotService.swift
//  gemini-shortcut
//
//  Created by AI on 4/14/26.
//

import AppKit
import ScreenCaptureKit

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}

enum ScreenshotService {
    /// Captures the display that hosts `screen`. Falls back to the first available display.
    static func captureScreen(for screen: NSScreen? = nil) async -> NSImage? {
        do {
            let content = try await SCShareableContent.current
            let targetID = screen?.displayID
            let display = content.displays.first { targetID != nil && $0.displayID == targetID }
                       ?? content.displays.first
            guard let display else { return nil }
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            return NSImage(cgImage: image, size: .zero)
        } catch {
            print("Screenshot error: \(error)")
            return nil
        }
    }
    
    static func pngData(from image: NSImage) -> Data? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        return rep.representation(using: .png, properties: [:])
    }
}
