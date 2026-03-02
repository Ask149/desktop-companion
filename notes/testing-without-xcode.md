# Testing on macOS without Xcode (Command Line Tools only)

## Problem
Neither XCTest nor Swift Testing framework tests can be *executed* via `swift test` without full Xcode installed.
- `import XCTest` → "no such module" at compile time
- `import Testing` → compiles with `-F` framework flags, but `swift test` produces no output (test discovery fails, `.xctest` bundle needs `xctest` runner which doesn't exist)

## Solution
Use an **executable test runner** instead of a `.testTarget`:
- Define as `.executableTarget` in Package.swift
- Uses `@testable import CompanionCore` 
- Manual assertion functions (no framework needed)
- Run via `swift run CompanionTests`
- Exit code 0 = pass, 1 = fail

## Swift 6 Gotchas
- Top-level vars in `main.swift` are `@MainActor`-isolated
- Functions that mutate them need `@MainActor` annotation
- `CritterRenderer.makeIcon()` needs `@MainActor` (uses NSImage/NSGraphicsContext)

## Project Structure
```
Sources/CompanionCore/   ← library target (all testable logic, public access)
Sources/DesktopCompanion/ ← executable (thin wrapper)
Tests/CompanionTests/     ← executable test runner (swift run CompanionTests)
```
