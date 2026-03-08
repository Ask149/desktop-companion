// Sources/DesktopCompanion/Views/OverlayWindow.swift
import AppKit
import SwiftUI
import CompanionCore
import QuartzCore

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
    /// Called when Escape is pressed — caller decides whether to interrupt speech or dismiss.
    var onEscape: (() -> Void)?

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
        w.contentView?.wantsLayer = true

        // Start transparent + slightly scaled down, animate in
        w.alphaValue = 0
        w.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)

        // Apply initial scale via layer transform
        if let layer = w.contentView?.layer {
            layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            layer.transform = CATransform3DMakeScale(0.97, 0.97, 1.0)
        }

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.3
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1.0)
            w.animator().alphaValue = 1
        }

        // Explicit CABasicAnimation for layer scale (implicit animations are disabled on NSView layers)
        if let layer = w.contentView?.layer {
            let scaleAnim = CABasicAnimation(keyPath: "transform")
            scaleAnim.fromValue = NSValue(caTransform3D: CATransform3DMakeScale(0.97, 0.97, 1.0))
            scaleAnim.toValue = NSValue(caTransform3D: CATransform3DIdentity)
            scaleAnim.duration = 0.3
            scaleAnim.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1.0)
            scaleAnim.isRemovedOnCompletion = false
            scaleAnim.fillMode = .forwards
            layer.add(scaleAnim, forKey: "showScale")
            layer.transform = CATransform3DIdentity
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

        // Explicit CABasicAnimation for layer scale on dismiss
        if let layer = w.contentView?.layer {
            let scaleAnim = CABasicAnimation(keyPath: "transform")
            scaleAnim.fromValue = NSValue(caTransform3D: CATransform3DIdentity)
            scaleAnim.toValue = NSValue(caTransform3D: CATransform3DMakeScale(0.98, 0.98, 1.0))
            scaleAnim.duration = 0.25
            scaleAnim.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0.0, 1.0, 1.0)
            scaleAnim.isRemovedOnCompletion = false
            scaleAnim.fillMode = .forwards
            layer.add(scaleAnim, forKey: "dismissScale")
            layer.transform = CATransform3DMakeScale(0.98, 0.98, 1.0)
        }

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0.0, 1.0, 1.0)
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
                if event.keyCode == 53 { // Escape key
                    self?.onEscape?()
                } else {
                    self?.dismiss()
                }
            }
            return event
        }

        // Global monitors as fallback — fire even if window loses key status
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            Task { @MainActor in
                self?.handleMouseMove(event)
            }
        }
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            Task { @MainActor in
                if event.keyCode == 53 { // Escape key
                    self?.onEscape?()
                } else {
                    self?.dismiss()
                }
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
