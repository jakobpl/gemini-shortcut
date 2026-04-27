import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    var monitor: Any?
    func applicationDidFinishLaunching(_ notification: Notification) {
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { event in
            // Handle event
            return event
        }
    }
}
