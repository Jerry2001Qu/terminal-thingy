import SwiftUI

struct IdleGlowView: View {
    let intensity: Double
    let pulsing: Bool

    @State private var phase: Double = 0

    private let glowColor1 = Color(red: 0.2, green: 0.5, blue: 1.0)
    private let glowColor2 = Color(red: 0.3, green: 0.7, blue: 1.0)
    private let glowColor3 = Color(red: 0.1, green: 0.4, blue: 1.0)

    // Remap intensity: starts at what was previously max, scales up further
    private var i: Double { 0.6 + intensity * 0.4 }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Layer 1: Wide outer glow — very visible on all edges
                RoundedRectangle(cornerRadius: 0)
                    .stroke(
                        glowColor1.opacity(i * wave(offset: 0) * 0.7),
                        lineWidth: i * 30
                    )
                    .blur(radius: i * 40)

                // Layer 2: Mid glow
                RoundedRectangle(cornerRadius: 0)
                    .stroke(
                        glowColor2.opacity(i * wave(offset: 2) * 0.8),
                        lineWidth: i * 16
                    )
                    .blur(radius: i * 20)

                // Layer 3: Sharp inner edge
                RoundedRectangle(cornerRadius: 0)
                    .stroke(
                        glowColor3.opacity(i * wave(offset: 4) * 0.9),
                        lineWidth: i * 6
                    )
                    .blur(radius: i * 8)

                // Layer 4: Extra bright border line
                RoundedRectangle(cornerRadius: 0)
                    .stroke(
                        glowColor2.opacity(i * wave(offset: 1) * 0.6),
                        lineWidth: i * 2
                    )

                // Edge accents — top, bottom, left, right (not just corners)
                ForEach(0..<8, id: \.self) { idx in
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    glowColor2.opacity(i * wave(offset: Double(idx) * 0.8) * 0.5),
                                    Color.clear
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: i * 120
                            )
                        )
                        .frame(width: i * 240, height: i * 240)
                        .position(accentPosition(idx, in: geo.size))
                }
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 5).repeatForever(autoreverses: false)) {
                phase = .pi * 2
            }
        }
    }

    private func wave(offset: Double) -> Double {
        let base = sin(phase + offset) * 0.2 + 0.8
        let secondary = sin(phase * 1.7 + offset * 0.5) * 0.1 + 0.9
        return base * secondary
    }

    /// 8 accent points: 4 corners + 4 edge midpoints
    private func accentPosition(_ index: Int, in size: CGSize) -> CGPoint {
        let w = size.width
        let h = size.height
        switch index {
        case 0: return CGPoint(x: 0, y: 0)             // top-left
        case 1: return CGPoint(x: w, y: 0)              // top-right
        case 2: return CGPoint(x: 0, y: h)              // bottom-left
        case 3: return CGPoint(x: w, y: h)              // bottom-right
        case 4: return CGPoint(x: w * 0.5, y: 0)        // top-center
        case 5: return CGPoint(x: w * 0.5, y: h)        // bottom-center
        case 6: return CGPoint(x: 0, y: h * 0.5)        // left-center
        case 7: return CGPoint(x: w, y: h * 0.5)        // right-center
        default: return .zero
        }
    }
}
