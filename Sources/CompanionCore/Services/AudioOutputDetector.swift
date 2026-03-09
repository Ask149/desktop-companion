// Sources/CompanionCore/Services/AudioOutputDetector.swift
import Foundation
import CoreAudio
import os.log

private let logger = Logger(subsystem: "com.ask149.friday", category: "AudioOutputDetector")

/// Detects whether audio output is via built-in speakers or external (headphones/Bluetooth).
/// Used to adjust post-TTS delay — external output has no echo risk.
@MainActor
public final class AudioOutputDetector {
    /// Whether the current audio output is built-in speakers (echo risk).
    public var isBuiltInSpeaker: Bool {
        let transportType = Self.getOutputTransportType()
        let isBuiltIn = transportType == kAudioDeviceTransportTypeBuiltIn
        logger.debug("Audio output transport: \(transportType), isBuiltIn: \(isBuiltIn)")
        return isBuiltIn
    }

    public init() {}

    /// Get the transport type of the default output device.
    /// Returns kAudioDeviceTransportTypeBuiltIn for built-in speakers,
    /// kAudioDeviceTransportTypeUSB, kAudioDeviceTransportTypeBluetooth, etc. for external.
    private nonisolated static func getOutputTransportType() -> UInt32 {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0, nil,
            &size,
            &deviceID
        )

        guard status == noErr else {
            logger.error("Failed to get default output device: \(status)")
            return kAudioDeviceTransportTypeBuiltIn // assume built-in (safe default)
        }

        var transportType: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0, nil,
            &size,
            &transportType
        )

        guard status == noErr else {
            logger.error("Failed to get transport type: \(status)")
            return kAudioDeviceTransportTypeBuiltIn // assume built-in (safe default)
        }

        return transportType
    }
}
