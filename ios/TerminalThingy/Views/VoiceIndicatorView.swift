import SwiftUI

struct VoiceIndicatorView: View {
    @ObservedObject var speechService: SpeechCommandService
    @State private var flashColor: Color?

    private let glowColor = Color(red: 0.25, green: 0.55, blue: 1.0)

    var body: some View {
        VStack {
            Spacer()
            HStack(alignment: .top, spacing: 6) {
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
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(flashColor ?? .clear)
                            .opacity(flashColor != nil ? 0.3 : 0)
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .animation(.none, value: speechService.lastHeard)
            .padding(.horizontal, 40)
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

        return FlowText(words: words, cmdStart: cmdStart, glowColor: glowColor, speechService: speechService)
    }
}

/// Wrapping text that highlights command keywords
private struct FlowText: View {
    let words: [String]
    let cmdStart: Int
    let glowColor: Color
    let speechService: SpeechCommandService

    var body: some View {
        Text(attributedString)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var attributedString: AttributedString {
        var result = AttributedString()
        for (index, word) in words.enumerated() {
            if index > 0 {
                result.append(AttributedString(" "))
            }
            var part = AttributedString(word)
            let isCommand = index == cmdStart && speechService.isCommandWord(word)
            let isWakeWord = cmdStart > 0 && index == 0 && speechService.isCommandWord(word)

            if isCommand || isWakeWord {
                part.foregroundColor = UIColor(glowColor)
                part.font = .caption.bold()
            } else {
                part.foregroundColor = .secondaryLabel
                part.font = .caption
            }
            result.append(part)
        }
        return result
    }
}
