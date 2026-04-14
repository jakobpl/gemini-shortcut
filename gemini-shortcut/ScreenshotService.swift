//
//  ScreenshotService.swift
//  gemini-shortcut
//
//  Created by AI on 4/14/26.
//

import AppKit
import ScreenCaptureKit

enum ScreenshotService {
    static func captureScreen() async -> NSImage? {
        do {
            let content = try await SCShareableContent.current
            guard let display = content.displays.first else { return nil }
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
