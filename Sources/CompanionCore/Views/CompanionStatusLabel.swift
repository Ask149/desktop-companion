// Sources/CompanionCore/Views/CompanionStatusLabel.swift
import AppKit
import Combine

/// Manages the animated menu bar icon, updating it based on companion state.
/// Inspired by OpenClaw's CritterStatusLabel — timer-driven animation with state variables.
@MainActor
public class CompanionStatusLabel {
    private let statusItem: NSStatusItem
    private var timer: Timer?
    private var tickCount: Int = 0

    // Animation state
    private var blinkAmount: CGFloat = 0
    private var wiggleAmount: CGFloat = 0
    private var isBlinking = false

    // Current mode — set externally by CompanionState
    public var mode: CompanionMode = .idle {
        didSet { updateIcon() }
    }

    public init(statusItem: NSStatusItem) {
        self.statusItem = statusItem
        updateIcon()
        startAnimationLoop()
    }

    private func startAnimationLoop() {
        // Tick every 0.5 seconds for animation
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
    }

    private func tick() {
        tickCount += 1

        // Don't animate in sleeping or dead modes
        guard mode == .idle || mode == .thinking || mode == .alert else {
            blinkAmount = 0
            wiggleAmount = 0
            updateIcon()
            return
        }

        // Blink every 6-10 ticks (3-5 seconds)
        if !isBlinking && tickCount % Int.random(in: 6...10) == 0 {
            blink()
        }

        // Wiggle every 15-25 ticks (7.5-12.5 seconds) in idle mode
        if mode == .idle && tickCount % Int.random(in: 15...25) == 0 {
            wiggle()
        }

        // Thinking mode: faster wiggle (leg scurry)
        if mode == .thinking && tickCount % 2 == 0 {
            wiggleAmount = CGFloat.random(in: -0.3...0.3)
            updateIcon()
        }
    }

    private func blink() {
        isBlinking = true
        blinkAmount = 1
        updateIcon()

        // Open eyes after 0.15 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.blinkAmount = 0
            self?.isBlinking = false
            self?.updateIcon()
        }
    }

    private func wiggle() {
        wiggleAmount = CGFloat.random(in: -0.6...0.6)
        updateIcon()

        // Return to center after 0.3 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.wiggleAmount = 0
            self?.updateIcon()
        }
    }

    private func updateIcon() {
        let icon = CritterRenderer.makeIcon(mode: mode, blink: blinkAmount, wiggle: wiggleAmount)
        statusItem.button?.image = icon
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }
}
