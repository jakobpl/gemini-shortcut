import AppKit

extension NSScrollView {
    @objc var customMouseDownCanMoveWindow: Bool {
        return true
    }
    
    static func swizzleMouseDownCanMoveWindow() {
        let originalMethod = class_getInstanceMethod(NSScrollView.self, #selector(getter: NSScrollView.mouseDownCanMoveWindow))
        let swizzledMethod = class_getInstanceMethod(NSScrollView.self, #selector(getter: NSScrollView.customMouseDownCanMoveWindow))
        if let originalMethod = originalMethod, let swizzledMethod = swizzledMethod {
            method_exchangeImplementations(originalMethod, swizzledMethod)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSScrollView.swizzleMouseDownCanMoveWindow()
    }
}
