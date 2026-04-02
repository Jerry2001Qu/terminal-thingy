import SwiftUI

struct IdleGlowView: View {
    let intensity: Double

    private let glowColor = Color(red: 0.25, green: 0.55, blue: 1.0)

    private var i: Double { intensity > 0 ? 0.7 + intensity * 0.3 : 0 }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: intensity == 0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let speed = 0.05 + intensity * 0.15

            GeometryReader { geo in
                let glowDepth = 100.0 + i * 100.0

                ZStack {
                    // Base border glow
                    RoundedRectangle(cornerRadius: 0)
                        .stroke(glowColor.opacity(i * 0.9), lineWidth: 10)
                        .blur(radius: 15)

                    // Wide diffuse layer
                    RoundedRectangle(cornerRadius: 0)
                        .stroke(glowColor.opacity(i * 0.7), lineWidth: 30)
                        .blur(radius: 40)

                    // Extra wide ambient wash
                    RoundedRectangle(cornerRadius: 0)
                        .stroke(glowColor.opacity(i * 0.3), lineWidth: 50)
                        .blur(radius: 60)

                    // Top edge
                    edgeGlow(
                        width: geo.size.width, height: glowDepth,
                        gradient: .top,
                        brightness: edgeBrightness(t, speed: speed, edgeOffset: 0)
                    )
                    .frame(width: geo.size.width, height: glowDepth)
                    .position(x: geo.size.width / 2, y: 0)

                    // Bottom edge
                    edgeGlow(
                        width: geo.size.width, height: glowDepth,
                        gradient: .bottom,
                        brightness: edgeBrightness(t, speed: speed, edgeOffset: 2)
                    )
                    .frame(width: geo.size.width, height: glowDepth)
                    .position(x: geo.size.width / 2, y: geo.size.height)

                    // Left edge
                    edgeGlow(
                        width: glowDepth, height: geo.size.height,
                        gradient: .leading,
                        brightness: edgeBrightness(t, speed: speed, edgeOffset: 3)
                    )
                    .frame(width: glowDepth, height: geo.size.height)
                    .position(x: 0, y: geo.size.height / 2)

                    // Right edge
                    edgeGlow(
                        width: glowDepth, height: geo.size.height,
                        gradient: .trailing,
                        brightness: edgeBrightness(t, speed: speed, edgeOffset: 1)
                    )
                    .frame(width: glowDepth, height: geo.size.height)
                    .position(x: geo.size.width, y: geo.size.height / 2)
                }
            }
        }
    }

    /// A single edge glow strip — gradient from bright at edge to transparent inward
    private func edgeGlow(width: CGFloat, height: CGFloat, gradient: Edge.Set, brightness: Double) -> some View {
        let opacity = i * brightness

        let startPoint: UnitPoint
        let endPoint: UnitPoint

        switch gradient {
        case .top:
            startPoint = .top; endPoint = .bottom
        case .bottom:
            startPoint = .bottom; endPoint = .top
        case .leading:
            startPoint = .leading; endPoint = .trailing
        case .trailing:
            startPoint = .trailing; endPoint = .leading
        default:
            startPoint = .top; endPoint = .bottom
        }

        return LinearGradient(
            colors: [
                glowColor.opacity(opacity),
                glowColor.opacity(opacity * 0.6),
                glowColor.opacity(opacity * 0.2),
                Color.clear
            ],
            startPoint: startPoint,
            endPoint: endPoint
        )
        .blur(radius: 25)
    }

    /// All edges pulse in sync
    private func edgeBrightness(_ t: Double, speed: Double, edgeOffset: Double) -> Double {
        // Primary pulse
        let wave1 = sin(t * speed * .pi * 4) * 0.45 + 0.55

        // Secondary rhythm
        let wave2 = sin(t * speed * 2.6 * .pi * 2 + 0.7) * 0.3 + 0.7

        // Slow breathe
        let wave3 = sin(t * 0.3) * 0.2 + 0.8

        return max(wave1 * wave2 * wave3, 0.2)
    }
}
