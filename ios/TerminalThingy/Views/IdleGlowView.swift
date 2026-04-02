import SwiftUI

struct IdleGlowView: View {
    let intensity: Double
    let pulsing: Bool

    @State private var phase: Double = 0

    private let glowColor1 = Color(red: 0.2, green: 0.5, blue: 1.0)  // Soft blue
    private let glowColor2 = Color(red: 0.3, green: 0.7, blue: 1.0)  // Lighter blue
    private let glowColor3 = Color(red: 0.1, green: 0.3, blue: 0.9)  // Deeper blue

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Layer 1: Outer soft glow
                RoundedRectangle(cornerRadius: 0)
                    .stroke(
                        glowColor1.opacity(intensity * wave(offset: 0) * 0.3),
                        lineWidth: intensity * 12
                    )
                    .blur(radius: intensity * 25)

                // Layer 2: Mid glow with phase offset
                RoundedRectangle(cornerRadius: 0)
                    .stroke(
                        glowColor2.opacity(intensity * wave(offset: 2) * 0.4),
                        lineWidth: intensity * 6
                    )
                    .blur(radius: intensity * 12)

                // Layer 3: Inner crisp edge
                RoundedRectangle(cornerRadius: 0)
                    .stroke(
                        glowColor3.opacity(intensity * wave(offset: 4) * 0.5),
                        lineWidth: intensity * 2
                    )
                    .blur(radius: intensity * 4)

                // Corner accents — brighter glow at corners for organic feel
                ForEach(0..<4, id: \.self) { corner in
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    glowColor2.opacity(intensity * wave(offset: Double(corner) * 1.5) * 0.4),
                                    Color.clear
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: intensity * 80
                            )
                        )
                        .frame(width: intensity * 160, height: intensity * 160)
                        .position(cornerPosition(corner, in: geo.size))
                }
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 6).repeatForever(autoreverses: false)) {
                phase = .pi * 2
            }
        }
    }

    /// Smooth wave function for organic pulsing. Each layer has a different offset.
    private func wave(offset: Double) -> Double {
        let base = sin(phase + offset) * 0.3 + 0.7  // Oscillates between 0.4 and 1.0
        let secondary = sin(phase * 1.7 + offset * 0.5) * 0.15 + 0.85  // Subtle secondary rhythm
        return base * secondary
    }

    private func cornerPosition(_ index: Int, in size: CGSize) -> CGPoint {
        switch index {
        case 0: return CGPoint(x: 0, y: 0)
        case 1: return CGPoint(x: size.width, y: 0)
        case 2: return CGPoint(x: 0, y: size.height)
        case 3: return CGPoint(x: size.width, y: size.height)
        default: return .zero
        }
    }
}
