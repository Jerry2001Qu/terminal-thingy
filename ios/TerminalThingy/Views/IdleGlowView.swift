import SwiftUI

struct IdleGlowView: View {
    let intensity: Double
    let pulsing: Bool

    @State private var phase: Double = 0
    @State private var appeared = false

    private let glowColor1 = Color(red: 0.2, green: 0.5, blue: 1.0)
    private let glowColor2 = Color(red: 0.3, green: 0.7, blue: 1.0)
    private let glowColor3 = Color(red: 0.1, green: 0.4, blue: 1.0)

    // Remap: starts strong, gets stronger
    private var i: Double { 0.6 + intensity * 0.4 }

    // Quick fade-in over ~1s when first appearing
    private var fadeIn: Double { appeared ? 1.0 : 0.0 }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack {
                // Layer 1: Wide outer glow
                RoundedRectangle(cornerRadius: 0)
                    .stroke(
                        glowColor1.opacity(i * fadeIn * wave(offset: 0) * 0.7),
                        lineWidth: i * 30
                    )
                    .blur(radius: i * 40)

                // Layer 2: Mid glow
                RoundedRectangle(cornerRadius: 0)
                    .stroke(
                        glowColor2.opacity(i * fadeIn * wave(offset: 2) * 0.8),
                        lineWidth: i * 16
                    )
                    .blur(radius: i * 20)

                // Layer 3: Sharp inner edge
                RoundedRectangle(cornerRadius: 0)
                    .stroke(
                        glowColor3.opacity(i * fadeIn * wave(offset: 4) * 0.9),
                        lineWidth: i * 6
                    )
                    .blur(radius: i * 8)

                // Layer 4: Crisp border
                RoundedRectangle(cornerRadius: 0)
                    .stroke(
                        glowColor2.opacity(i * fadeIn * wave(offset: 1) * 0.6),
                        lineWidth: i * 2
                    )

                // Traveling wave blobs — orbit around the perimeter
                ForEach(0..<6, id: \.self) { idx in
                    let blobPhase = phase + Double(idx) * (.pi * 2 / 6)
                    let pos = perimeterPosition(phase: blobPhase, in: geo.size)

                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    glowColor2.opacity(i * fadeIn * blobWave(idx: idx) * 0.6),
                                    glowColor1.opacity(i * fadeIn * blobWave(idx: idx) * 0.2),
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

                // Secondary slower blobs moving the opposite direction
                ForEach(0..<4, id: \.self) { idx in
                    let blobPhase = -phase * 0.7 + Double(idx) * (.pi * 2 / 4) + 1.0
                    let pos = perimeterPosition(phase: blobPhase, in: geo.size)

                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    glowColor3.opacity(i * fadeIn * 0.4),
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
        .onAppear {
            withAnimation(.easeIn(duration: 0.8)) {
                appeared = true
            }
            // Use 20π so both sin(phase) and sin(phase*1.7) loop cleanly (LCM of periods)
            withAnimation(.linear(duration: 80).repeatForever(autoreverses: false)) {
                phase = .pi * 20
            }
        }
        .onDisappear {
            appeared = false
            phase = 0
        }
    }

    private func wave(offset: Double) -> Double {
        let base = sin(phase + offset) * 0.2 + 0.8
        let secondary = sin(phase * 1.7 + offset * 0.5) * 0.1 + 0.9
        return base * secondary
    }

    private func blobWave(idx: Int) -> Double {
        let offset = Double(idx) * 1.3
        return sin(phase * 2.3 + offset) * 0.3 + 0.7
    }

    /// Maps a phase angle to a point traveling along the rectangle perimeter
    private func perimeterPosition(phase: Double, in size: CGSize) -> CGPoint {
        let w = size.width
        let h = size.height
        let perimeter = 2 * (w + h)

        // Normalize phase to 0...1 along the perimeter
        var t = phase.truncatingRemainder(dividingBy: .pi * 2)
        if t < 0 { t += .pi * 2 }
        let frac = t / (.pi * 2)
        let dist = frac * perimeter

        if dist < w {
            // Top edge: left to right
            return CGPoint(x: dist, y: 0)
        } else if dist < w + h {
            // Right edge: top to bottom
            return CGPoint(x: w, y: dist - w)
        } else if dist < 2 * w + h {
            // Bottom edge: right to left
            return CGPoint(x: w - (dist - w - h), y: h)
        } else {
            // Left edge: bottom to top
            return CGPoint(x: 0, y: h - (dist - 2 * w - h))
        }
    }
}
