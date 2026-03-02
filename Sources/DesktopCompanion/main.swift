import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create status bar item with fixed width
        statusItem = NSStatusBar.system.statusItem(withLength: 28)

        if let button = statusItem.button {
            // Temporary: use SF Symbol as placeholder until we build CritterRenderer
            button.image = NSImage(systemSymbolName: "face.smiling", accessibilityDescription: "Companion")
            button.action = #selector(togglePopover)
            button.target = self
        }

        // Create popover
        popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 400)
        popover.behavior = .transient // Close when clicking outside
        popover.contentViewController = NSHostingController(
            rootView: Text("Desktop Companion").padding()
        )
    }

    @objc func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // No dock icon
app.run()
