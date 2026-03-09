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

        // Permission gate: if user tries to open overlay without voice permissions,
        // open System Settings instead of covering the permission dialog.
        state.onPermissionNeeded = {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition") {
                NSWorkspace.shared.open(url)
            }
        }
        // Escape key: interrupt speech if speaking, otherwise dismiss
        overlay.onEscape = { [weak self] in
            guard let self = self else { return }
            if self.state.voiceOutput.isSpeaking {
                self.state.interruptSpeech()
            } else {
                self.state.hideOverlay()
            }
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
        let expr = state.mood.expression
        let c = expr.color
        let moodColor = Color(red: c.red, green: c.green, blue: c.blue)

        ZStack {
            // Ambient background
            BackgroundView(mood: state.mood)

            VStack(spacing: 0) {
                // Top padding
                Spacer().frame(height: 60)

                // Face with listening ring — scaled to 85% for more conversation room
                ZStack {
                    ListeningRingView(
                        mood: state.mood,
                        isListening: state.isVoiceListening,
                        audioLevel: state.audioLevel
                    )

                    FaceView(
                        mood: state.mood,
                        mouthOpenness: state.mouthOpenness,
                        blinkAmount: state.blinkAmount,
                        isSpeaking: state.voiceOutput.isSpeaking
                    )
                    .onTapGesture {
                        state.interruptSpeech()
                    }
                }
                .scaleEffect(0.85)

                // Unified state label — replaces mood pill + interrupt hint
                stateLabel(moodColor: moodColor)
                    .padding(.top, 8)

                // 16px gap before conversation
                Spacer().frame(height: 16)

                // Conversation fills all remaining height, bottom-anchored
                ConversationView(
                    messages: state.sessionMessages,
                    partialTranscription: state.partialTranscription,
                    partialAssistantResponse: state.partialAssistantResponse,
                    streamStatus: state.streamStatus,
                    isChatting: state.isChatting,
                    mood: state.mood
                )

                // Bottom safe area
                Spacer().frame(height: 40)
            }
        }
    }

    /// State indicator: shows current phase (listening / thinking / tap to interrupt / mood reason).
    @ViewBuilder
    private func stateLabel(moodColor: Color) -> some View {
        let (text, color, opacity) = stateLabelContent(moodColor: moodColor)

        Text(text)
            .font(.system(.caption, design: .rounded))
            .foregroundStyle(color.opacity(opacity))
            .animation(FridayAnimation.micro, value: state.isVoiceListening)
            .animation(FridayAnimation.micro, value: state.isChatting)
            .animation(FridayAnimation.micro, value: state.voiceOutput.isSpeaking)
    }

    private func stateLabelContent(moodColor: Color) -> (String, Color, Double) {
        if state.isVoiceListening && !state.isChatting {
            return ("Listening", moodColor, 0.6)
        } else if state.isChatting && state.partialAssistantResponse.isEmpty {
            return ("Thinking...", .white, 0.4)
        } else if state.voiceOutput.isSpeaking {
            return ("tap to interrupt", .white, 0.2)
        } else if !state.moodReason.isEmpty {
            return (state.moodReason, .white, 0.3)
        } else {
            return ("", .white, 0)
        }
    }
}

// --- App Launch ---
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
