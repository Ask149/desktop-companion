// Sources/CompanionCore/Services/IdleDetector.swift
import AppKit
import CoreGraphics
import Foundation
import IOKit

/// Monitors system idle time (seconds since last keyboard/mouse input).
/// Uses IOKit HIDIdleTime — no accessibility permissions required.
@MainActor
public final class IdleDetector {
    /// Callback when idle threshold is reached.
    public var onIdleStart: (() -> Void)?
    /// Callback when user becomes active again (mouse/keyboard after idle).
    public var onIdleEnd: (() -> Void)?

    /// Idle threshold in seconds (default: 5 minutes).
    public var threshold: TimeInterval = 300

    private var timer: Timer?
    private var wasIdle = false

    /// Active hours (idle overlay only triggers during these hours).
    public var activeHoursStart: Int = 8  // 8 AM
    public var activeHoursEnd: Int = 22   // 10 PM

    public init() {}

    /// Start polling for idle state.
    public func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.check()
            }
        }
    }

    /// Stop polling.
    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Current system idle time in seconds.
    public func systemIdleTime() -> TimeInterval {
        var iter: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IOHIDSystem"),
            &iter
        )
        guard result == KERN_SUCCESS else { return 0 }
        defer { IOObjectRelease(iter) }

        let entry = IOIteratorNext(iter)
        guard entry != 0 else { return 0 }
        defer { IOObjectRelease(entry) }

        var props: Unmanaged<CFMutableDictionary>?
        let propResult = IORegistryEntryCreateCFProperties(
            entry, &props, kCFAllocatorDefault, 0
        )
        guard propResult == KERN_SUCCESS,
              let dict = props?.takeRetainedValue() as? [String: Any],
              let nanos = dict["HIDIdleTime"] as? Int64 else {
            return 0
        }

        return TimeInterval(nanos) / 1_000_000_000
    }

    // MARK: - Private

    private func check() {
        // Don't trigger outside active hours
        let hour = Calendar.current.component(.hour, from: Date())
        guard hour >= activeHoursStart && hour < activeHoursEnd else {
            if wasIdle {
                wasIdle = false
                onIdleEnd?()
            }
            return
        }

        // Don't trigger if a full-screen app is in front (e.g., watching a movie)
        if isFullScreenAppActive() {
            return
        }

        let idle = systemIdleTime()

        if !wasIdle && idle >= threshold {
            wasIdle = true
            onIdleStart?()
        } else if wasIdle && idle < 2 {
            // User became active (idle time reset to near 0)
            wasIdle = false
            onIdleEnd?()
        }
    }

    private func isFullScreenAppActive() -> Bool {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return false }
        // Skip if it's our own app
        if frontApp.bundleIdentifier == Bundle.main.bundleIdentifier { return false }

        // Check main screen for full-screen window
        guard let mainScreen = NSScreen.main else { return false }
        let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        for window in windowList {
            guard let ownerPID = window[kCGWindowOwnerPID as String] as? Int32,
                  ownerPID == frontApp.processIdentifier,
                  let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
                  let width = bounds["Width"],
                  let height = bounds["Height"] else { continue }
            // If the window covers the full screen, it's likely full-screen
            if width >= mainScreen.frame.width && height >= mainScreen.frame.height {
                return true
            }
        }
        return false
    }
}
