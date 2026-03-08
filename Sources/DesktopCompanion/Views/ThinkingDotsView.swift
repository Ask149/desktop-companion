// Sources/DesktopCompanion/Views/ThinkingDotsView.swift
import SwiftUI
import CompanionCore

/// Three bouncing dots indicating Friday is thinking — iMessage style.
struct ThinkingDotsView: View {
    let mood: Mood

    @State private var animating = false

    var body: some View {
        let expr = mood.expression
        let c = expr.color
        let dotColor = Color(red: c.red, green: c.green, blue: c.blue)

        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(dotColor.opacity(0.5))
                    .frame(width: 6, height: 6)
                    .offset(y: animating ? -6 : 0)
                    .animation(
                        .spring(duration: 0.4, bounce: 0.3)
                        .repeatForever(autoreverses: true)
                        .delay(Double(index) * 0.15),
                        value: animating
                    )
            }
        }
        .onAppear { animating = true }
        .onDisappear { animating = false }
    }
}
