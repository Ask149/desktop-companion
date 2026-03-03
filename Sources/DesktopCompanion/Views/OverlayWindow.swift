// Sources/DesktopCompanion/Views/OverlayWindow.swift
import AppKit
import SwiftUI
import CompanionCore

/// NSPanel subclass that can become key — required for receiving
/// mouseMoved and keyDown events with borderless style.
private class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Manages the full-screen overlay window for Friday.
/// - Covers the main screen with pure black
/// - Dismisses on mouse movement (> 5px delta) or keyboard input
/// - Fades in/out with 0.3s animation
@MainActor
final class OverlayWindow {
    private var window: NSWindow?
    private var mouseMonitor: Any?
    private var keyMonitor: Any?
    private var globalMouseMonitor: Any?
    private var globalKeyMonitor: Any?
    private var lastMouseLocation: NSPoint?
    private let dismissThreshold: CGFloat = 10 // pixels per event (not cumulative)

    /// Minimum time between show/dismiss to prevent rapid cycling.
    private var lastTransition: Date = .distantPast
    private let debounceInterval: TimeInterval = 3

    var onDismiss: (() -> Void)?

    /// Show the overlay with fade-in animation.
    func show(contentView: some View) {
        guard window == nil else { return }
        guard Date().timeIntervalSince(lastTransition) >= debounceInterval else { return }

        guard let screen = NSScreen.main else { return }
        let frame = screen.frame

        let w = KeyablePanel(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        w.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow)))
        w.backgroundColor = .black
        w.isOpaque = true
        w.hasShadow = false
        w.ignoresMouseEvents = false
        w.acceptsMouseMovedEvents = true
        w.hidesOnDeactivate = false
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        w.contentView = NSHostingView(rootView: contentView)

        // Start transparent, fade in
        w.alphaValue = 0
        w.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.3
            w.animator().alphaValue = 1
        }

        self.window = w
        self.lastMouseLocation = NSEvent.mouseLocation
        self.lastTransition = Date()

        installMonitors()
    }

    /// Dismiss the overlay with fade-out animation.
    func dismiss() {
        guard let w = window else { return }
        guard Date().timeIntervalSince(lastTransition) >= debounceInterval else { return }

        lastTransition = Date()
        removeMonitors()

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            w.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            // completionHandler runs on main thread for AppKit animations
            Task { @MainActor in
                w.orderOut(nil)
                self?.window = nil
                self?.onDismiss?()
            }
        })
    }

    var isVisible: Bool { window != nil && (window?.alphaValue ?? 0) > 0 }

    // MARK: - Private

    private func installMonitors() {
        // NSEvent monitor callbacks run on the main thread, but Swift 6 doesn't
        // know that. We use Task { @MainActor } to safely dispatch.
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            Task { @MainActor in
                self?.handleMouseMove(event)
            }
            return event
        }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            Task { @MainActor in
                self?.dismiss()
            }
            return event
        }

        // Global monitors as fallback — fire even if window loses key status
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            Task { @MainActor in
                self?.handleMouseMove(event)
            }
        }
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] _ in
            Task { @MainActor in
                self?.dismiss()
            }
        }
    }

    private func removeMonitors() {
        if let m = mouseMonitor { NSEvent.removeMonitor(m); mouseMonitor = nil }
        if let k = keyMonitor { NSEvent.removeMonitor(k); keyMonitor = nil }
        if let gm = globalMouseMonitor { NSEvent.removeMonitor(gm); globalMouseMonitor = nil }
        if let gk = globalKeyMonitor { NSEvent.removeMonitor(gk); globalKeyMonitor = nil }
    }

    private func handleMouseMove(_ event: NSEvent) {
        let current = NSEvent.mouseLocation
        guard let last = lastMouseLocation else {
            lastMouseLocation = current
            return
        }

        let dx = current.x - last.x
        let dy = current.y - last.y
        let distance = sqrt(dx * dx + dy * dy)

        // Always update baseline — track per-event delta, not cumulative
        // drift from origin. This prevents slow hand tremor from dismissing.
        lastMouseLocation = current

        if distance > dismissThreshold {
            dismiss()
        }
    }
}
