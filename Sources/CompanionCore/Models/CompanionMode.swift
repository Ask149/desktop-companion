// Sources/CompanionCore/Models/CompanionMode.swift
import Foundation

public enum CompanionMode: String, CaseIterable, Sendable {
    case idle       // Normal — gentle blink, occasional wiggle
    case thinking   // Processing a request
    case alert      // Heartbeat found something important
    case sleeping   // Outside active hours
    case dead       // Aidaemon unreachable
}
