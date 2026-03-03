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
    private let overlay = OverlayWindow()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // --- Menu Bar ---
        statusItem = NSStatusBar.system.statusItem(withLength: 28)

        if let button = statusItem.button {
            button.action = #selector(handleClick(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        statusLabel = CompanionStatusLabel(statusItem: statusItem)

        // Sync mode → menu bar icon
        state.$mode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] mode in self?.statusLabel.mode = mode }
            .store(in: &cancellables)

        // Sync mood → menu bar icon tint
        state.$mood
            .receive(on: DispatchQueue.main)
            .sink { [weak self] mood in self?.statusLabel.mood = mood }
            .store(in: &cancellables)

        // --- Popover ---
        popover = NSPopover()
        popover.contentSize = NSSize(width: 360, height: 520)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: PopoverView(state: state)
        )

        // --- Overlay ---
        overlay.onDismiss = { [weak self] in
            self?.state.hideOverlay()
        }

        // Show/hide overlay based on state
        state.$isOverlayVisible
            .receive(on: DispatchQueue.main)
            .sink { [weak self] visible in
                guard let self = self else { return }
                if visible {
                    let content = OverlayContentView(state: self.state)
                    self.overlay.show(contentView: content)
                } else {
                    self.overlay.dismiss()
                }
            }
            .store(in: &cancellables)
    }

    @objc func handleClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }

        if event.modifierFlags.contains(.option) {
            // Option-click → toggle overlay
            if state.isOverlayVisible {
                state.hideOverlay()
            } else {
                state.showOverlay()
            }
        } else if event.type == .rightMouseUp {
            // Right-click → context menu
            showContextMenu()
        } else {
            // Left-click → popover
            togglePopover()
        }
    }

    private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            Task { await state.refresh() }
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()

        let muteItem = NSMenuItem(
            title: state.isMuted ? "Unmute Voice" : "Mute Voice",
            action: #selector(toggleMute),
            keyEquivalent: ""
        )
        muteItem.target = self
        menu.addItem(muteItem)

        let overlayItem = NSMenuItem(
            title: "Show Friday (⌘⇧Space)",
            action: #selector(showOverlayAction),
            keyEquivalent: ""
        )
        overlayItem.target = self
        menu.addItem(overlayItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit Friday",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil // Remove after showing so left-click works again
    }

    @objc private func toggleMute() {
        state.isMuted.toggle()
    }

    @objc private func showOverlayAction() {
        state.showOverlay()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}

/// The SwiftUI content shown inside the full-screen overlay.
struct OverlayContentView: View {
    @ObservedObject var state: CompanionState

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 30) {
                Spacer()

                // The face
                FaceView(
                    mood: state.mood,
                    mouthOpenness: state.mouthOpenness,
                    blinkAmount: state.blinkAmount
                )

                // Greeting text
                if !state.greeting.isEmpty {
                    Text(state.greeting)
                        .font(.system(.title3, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 60)
                }

                // Mood indicator
                Text(state.moodReason)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.white.opacity(0.3))

                Spacer()

                // Transcript
                TranscriptView(
                    messages: state.session.messages,
                    partialTranscription: state.partialTranscription
                )

                // Listening indicator
                if state.voiceInput.isListening {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(.red)
                            .frame(width: 8, height: 8)
                        Text("Listening...")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    .padding(.bottom, 20)
                }

                Spacer().frame(height: 40)
            }
        }
    }
}

// --- App Launch ---
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
