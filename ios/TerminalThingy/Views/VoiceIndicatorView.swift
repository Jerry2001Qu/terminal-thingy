import SwiftUI

struct VoiceIndicatorView: View {
    @ObservedObject var speechService: SpeechCommandService
    @State private var flashColor: Color?

    private let glowColor = Color(red: 0.25, green: 0.55, blue: 1.0)

    var body: some View {
        VStack {
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "mic.fill")
                    .foregroundStyle(glowColor)

                if !speechService.lastHeard.isEmpty {
                    highlightedText
                        .transition(.identity)
                }
            }
            .font(.caption)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Capsule()
                            .fill(flashColor ?? .clear)
                            .opacity(flashColor != nil ? 0.3 : 0)
                    )
            )
            .clipShape(Capsule())
            .animation(.none, value: speechService.lastHeard)
            .padding(.bottom, 60)
        }
        .onChange(of: speechService.commandResult) { result in
            guard let result = result else { return }
            switch result {
            case .accepted:
                withAnimation(.easeIn(duration: 0.15)) {
                    flashColor = .green
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    withAnimation(.easeOut(duration: 0.3)) {
                        flashColor = nil
                    }
                }
            case .ignored:
                withAnimation(.easeIn(duration: 0.15)) {
                    flashColor = .red
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    withAnimation(.easeOut(duration: 0.3)) {
                        flashColor = nil
                    }
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                speechService.commandResult = nil
            }
        }
    }

    private var highlightedText: some View {
        let words = speechService.lastHeard.split(separator: " ").map(String.init)
        let cmdStart = speechService.commandStartIndex(in: words)

        return HStack(spacing: 4) {
            ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                let isCommand = index == cmdStart && speechService.isCommandWord(word)
                let isWakeWord = speechService.commandStartIndex(in: words) > 0 && index == 0 && speechService.isCommandWord(word)

                Text(word)
                    .fontWeight((isCommand || isWakeWord) ? .bold : .regular)
                    .foregroundStyle((isCommand || isWakeWord) ? glowColor : .secondary)
            }
        }
        .lineLimit(1)
    }
}

