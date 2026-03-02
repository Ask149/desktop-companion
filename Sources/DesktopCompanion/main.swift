// Sources/DesktopCompanion/main.swift
import AppKit
import SwiftUI
import Combine
import CompanionCore

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var statusLabel: CompanionStatusLabel!
    private var popover: NSPopover!
    private let state = CompanionState()
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create status bar item with fixed width
        statusItem = NSStatusBar.system.statusItem(withLength: 28)

        if let button = statusItem.button {
            button.action = #selector(togglePopover)
            button.target = self
        }

        // Set up animated icon
        statusLabel = CompanionStatusLabel(statusItem: statusItem)

        // Sync state.mode → statusLabel.mode via Combine
        state.$mode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] mode in
                self?.statusLabel.mode = mode
            }
            .store(in: &cancellables)

        // Create popover with SwiftUI views
        popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 450)
        popover.behavior = .transient // Close when clicking outside
        popover.contentViewController = NSHostingController(rootView: PopoverView(state: state))
    }

    @objc func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            // Refresh data when opening
            Task { await state.refresh() }
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // No dock icon
app.run()
