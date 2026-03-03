// Sources/DesktopCompanion/Views/OverlayWindow.swift
import AppKit
import SwiftUI
import CompanionCore

/// Manages the full-screen overlay window for Friday.
/// - Covers the main screen with pure black
/// - Dismisses on mouse movement (> 5px delta) or keyboard input
/// - Fades in/out with 0.3s animation
@MainActor
final class OverlayWindow {
    private var window: NSWindow?
    private var mouseMonitor: Any?
    private var keyMonitor: Any?
    private var lastMouseLocation: NSPoint?
    private let dismissThreshold: CGFloat = 5 // pixels

    /// Minimum time between show/dismiss to prevent rapid cycling.
    private var lastTransition: Date = .distantPast
    private let debounceInterval: TimeInterval = 2

    var onDismiss: (() -> Void)?

    /// Show the overlay with fade-in animation.
    func show(contentView: some View) {
        guard window == nil else { return }
        guard Date().timeIntervalSince(lastTransition) >= debounceInterval else { return }

        guard let screen = NSScreen.main else { return }
        let frame = screen.frame

        let w = NSWindow(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        w.level = .screenSaver
        w.backgroundColor = .black
        w.isOpaque = true
        w.hasShadow = false
        w.ignoresMouseEvents = false
        w.acceptsMouseMovedEvents = true
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        w.contentView = NSHostingView(rootView: contentView)

        // Start transparent, fade in
        w.alphaValue = 0
        w.orderFrontRegardless()

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
            MainActor.assumeIsolated {
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
        // know that. We use MainActor.assumeIsolated to bridge the gap.
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            MainActor.assumeIsolated {
                self?.handleMouseMove(event)
            }
            return event
        }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            MainActor.assumeIsolated {
                self?.dismiss()
            }
            return event
        }
    }

    private func removeMonitors() {
        if let m = mouseMonitor { NSEvent.removeMonitor(m); mouseMonitor = nil }
        if let k = keyMonitor { NSEvent.removeMonitor(k); keyMonitor = nil }
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

        if distance > dismissThreshold {
            dismiss()
        }
    }
}
