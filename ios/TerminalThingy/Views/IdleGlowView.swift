import SwiftUI

struct IdleGlowView: View {
    let intensity: Double

    private let glowColor1 = Color(red: 0.2, green: 0.5, blue: 1.0)
    private let glowColor2 = Color(red: 0.3, green: 0.7, blue: 1.0)
    private let glowColor3 = Color(red: 0.1, green: 0.4, blue: 1.0)

    private var i: Double { intensity > 0 ? 0.6 + intensity * 0.4 : 0 }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: intensity == 0)) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate

            GeometryReader { geo in
                ZStack {
                    // Layer 1: Wide outer glow
                    RoundedRectangle(cornerRadius: 0)
                        .stroke(
                            glowColor1.opacity(i * wave(phase, offset: 0) * 0.7),
                            lineWidth: i * 30
                        )
                        .blur(radius: i * 40)

                    // Layer 2: Mid glow
                    RoundedRectangle(cornerRadius: 0)
                        .stroke(
                            glowColor2.opacity(i * wave(phase, offset: 2) * 0.8),
                            lineWidth: i * 16
                        )
                        .blur(radius: i * 20)

                    // Layer 3: Sharp inner edge
                    RoundedRectangle(cornerRadius: 0)
                        .stroke(
                            glowColor3.opacity(i * wave(phase, offset: 4) * 0.9),
                            lineWidth: i * 6
                        )
                        .blur(radius: i * 8)

                    // Layer 4: Crisp border
                    RoundedRectangle(cornerRadius: 0)
                        .stroke(
                            glowColor2.opacity(i * wave(phase, offset: 1) * 0.6),
                            lineWidth: i * 2
                        )

                    // Traveling wave blobs — orbit clockwise, speed scales with intensity
                    let speed = 0.05 + intensity * 0.3
                    ForEach(0..<6, id: \.self) { idx in
                        let blobPhase = phase * speed + Double(idx) * (.pi * 2 / 6)
                        let pos = perimeterPosition(phase: blobPhase, in: geo.size)

                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [
                                        glowColor2.opacity(i * blobWave(phase, idx: idx) * 0.6),
                                        glowColor1.opacity(i * blobWave(phase, idx: idx) * 0.2),
                                        Color.clear
                                    ],
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: i * 100
                                )
                            )
                            .frame(width: i * 200, height: i * 200)
                            .position(pos)
                            .blur(radius: i * 15)
                    }

                    // Counter-rotating blobs
                    let counterSpeed = 0.03 + intensity * 0.2
                    ForEach(0..<4, id: \.self) { idx in
                        let blobPhase = -phase * counterSpeed + Double(idx) * (.pi * 2 / 4) + 1.0
                        let pos = perimeterPosition(phase: blobPhase, in: geo.size)

                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [
                                        glowColor3.opacity(i * 0.4),
                                        Color.clear
                                    ],
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: i * 80
                                )
                            )
                            .frame(width: i * 160, height: i * 160)
                            .position(pos)
                            .blur(radius: i * 20)
                    }
                }
            }
        }
    }

    // Continuous wave — no looping, just uses real time
    private func wave(_ phase: Double, offset: Double) -> Double {
        let a = sin(phase * 0.3 + offset) * 0.2 + 0.8
        let b = sin(phase * 0.17 + offset * 0.5) * 0.1 + 0.9
        return a * b
    }

    private func blobWave(_ phase: Double, idx: Int) -> Double {
        let offset = Double(idx) * 1.3
        return sin(phase * 0.23 + offset) * 0.3 + 0.7
    }

    private func perimeterPosition(phase: Double, in size: CGSize) -> CGPoint {
        let w = size.width
        let h = size.height
        let perimeter = 2 * (w + h)

        var t = phase.truncatingRemainder(dividingBy: .pi * 2)
        if t < 0 { t += .pi * 2 }
        let frac = t / (.pi * 2)
        let dist = frac * perimeter

        if dist < w {
            return CGPoint(x: dist, y: 0)
        } else if dist < w + h {
            return CGPoint(x: w, y: dist - w)
        } else if dist < 2 * w + h {
            return CGPoint(x: w - (dist - w - h), y: h)
        } else {
            return CGPoint(x: 0, y: h - (dist - 2 * w - h))
        }
    }
}
