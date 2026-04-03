import SwiftUI

struct TerminalView: View {
    let target: ConnectionTarget

    @Environment(\.dismiss) private var dismiss
    @StateObject private var grid = TerminalGrid()
    @StateObject private var client = WebSocketClient()
    @State private var isScrolledToBottom = true
    @State private var hasNewOutput = false
    @State private var showKeyboard = false
    @State private var viewWidth: CGFloat = 0
    @AppStorage("keepScreenAwake") private var keepScreenAwake = true
    @AppStorage("fitFontSize") private var fitFontSize: Double = 10.0
    @AppStorage("idleGlowEnabled") private var idleGlowEnabled = true
    @AppStorage("idleGlowSeconds") private var idleGlowSeconds: Double = 8
    @AppStorage("autoResize") private var autoResize = true
    @AppStorage("voiceCommandsEnabled") private var voiceCommandsEnabled = false
    @AppStorage("alwaysListening") private var alwaysListening = false
    @AppStorage("wakeWord") private var wakeWord = "terminal"
    @AppStorage("voiceTimeout") private var voiceTimeout: Double = 30
    @AppStorage("voiceLingerTime") private var voiceLingerTime: Double = 10
    @AppStorage("allowServerRecognition") private var allowServerRecognition = false
    @StateObject private var speechService = SpeechCommandService()
    @State private var lastActivityTime = Date()
    @State private var idleIntensity: Double = 0
    @State private var waitingForOutput = false
    @State private var hasAutoResized = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                Color.clear
                    .onAppear { viewWidth = geo.size.width }
                    .onChange(of: geo.size) { _ in
                        let newWidth = geo.size.width
                        if newWidth != viewWidth {
                            viewWidth = newWidth
                            if autoResize && client.state == .connected {
                                fitToPhone()
                            }
                        }
                    }
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            // Scrollback lines
                            ForEach(Array(grid.scrollbackLines.enumerated()), id: \.offset) { index, line in
                                TerminalCanvas(
                                    cells: [line],
                                    cols: grid.cols,
                                    rows: 1,
                                    cursorX: -1,
                                    cursorY: -1,
                                    availableWidth: geo.size.width
                                )
                            }

                            // Active viewport
                            TerminalCanvas(
                                cells: grid.cells,
                                cols: grid.cols,
                                rows: grid.rows,
                                cursorX: grid.cursorX,
                                cursorY: grid.cursorY,
                                availableWidth: geo.size.width
                            )
                            .id("viewport")

                            // Bottom sentinel — tracks whether we're scrolled to the bottom
                            GeometryReader { bottom in
                                Color.clear.preference(
                                    key: BottomVisibleKey.self,
                                    value: bottom.frame(in: .named("terminalScroll")).maxY <= geo.size.height + 50
                                )
                            }
                            .frame(height: 1)
                        }
                    }
                    .coordinateSpace(name: "terminalScroll")
                    .onPreferenceChange(BottomVisibleKey.self) { atBottom in
                        if atBottom != isScrolledToBottom {
                            isScrolledToBottom = atBottom
                        }
                        if atBottom {
                            hasNewOutput = false
                        }
                    }
                    .onChange(of: grid.cells) { _ in
                        if isScrolledToBottom {
                            withAnimation(.easeOut(duration: 0.1)) {
                                proxy.scrollTo("viewport", anchor: .bottom)
                            }
                        } else {
                            hasNewOutput = true
                        }
                    }
                    .onChange(of: grid.scrollbackLines.count) { _ in
                        if isScrolledToBottom {
                            proxy.scrollTo("viewport", anchor: .bottom)
                        } else {
                            hasNewOutput = true
                        }
                    }
                    .onTapGesture(count: 1) {
                        markUserInteraction()
                    }
                    .onTapGesture(count: 2) {
                        markUserInteraction()
                        showKeyboard.toggle()
                    }
                    .simultaneousGesture(
                        MagnificationGesture()
                            .onEnded { scale in
                                markUserInteraction()
                                guard grid.cols > 0 else { return }
                                let newCols = max(Int(CGFloat(grid.cols) / scale), 20)
                                let rows = grid.rows > 0 ? grid.rows : 24
                                client.sendResize(cols: newCols, rows: rows)
                            }
                    )
                    .onChange(of: showKeyboard) { _ in
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            withAnimation {
                                let anchor: UnitPoint = showKeyboard ? .bottom : (grid.scrollbackLines.isEmpty ? .top : .bottom)
                                proxy.scrollTo("viewport", anchor: anchor)
                            }
                        }
                    }

                    // "New output" / "Live" button
                    if !isScrolledToBottom {
                        Button {
                            isScrolledToBottom = true
                            hasNewOutput = false
                            withAnimation {
                                proxy.scrollTo("viewport", anchor: .bottom)
                            }
                        } label: {
                            HStack {
                                Image(systemName: hasNewOutput ? "arrow.down.circle.fill" : "arrow.down.circle")
                                Text(hasNewOutput ? "New output" : "Live")
                            }
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                        }
                        .padding(.bottom, 8)
                    }
                }

                // Keyboard input capture (zero-size, manages first responder + accessory bar)
                if showKeyboard {
                    TerminalKeyboardCapture(
                        onKey: { key in client.sendInput(key) },
                        onHideKeyboard: { showKeyboard = false }
                    )
                    .frame(width: 0, height: 0)
                }
            }
        }
        .overlay {
            ZStack {
                IdleGlowView(intensity: idleGlowEnabled ? idleIntensity : 0)
                    .allowsHitTesting(false)
                    .ignoresSafeArea(edges: [.bottom, .leading, .trailing])

                if speechService.isActive {
                    VoiceIndicatorView(speechService: speechService)
                        .allowsHitTesting(false)
                }
            }
        }
        .background(Color(.systemBackground))
        .navigationTitle(target.ip)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                connectionStatusView
            }
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 16) {
                    if !isAtFitSize {
                        Button {
                            markUserInteraction()
                            fitToPhone()
                        } label: {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                        }
                    }
                    if voiceCommandsEnabled && !alwaysListening {
                        Button {
                            if speechService.isListening {
                                speechService.stopLingering()
                                speechService.stopListening()
                            } else {
                                speechService.startListening(wakeWord: wakeWord, voiceTimeout: voiceTimeout, lingerTime: voiceLingerTime, allowServer: allowServerRecognition)
                                speechService.startLingering()
                            }
                        } label: {
                            Image(systemName: speechService.isListening ? "mic.fill" : "mic.slash")
                                .font(.body)
                                .foregroundStyle(speechService.isListening ? Color(red: 0.25, green: 0.55, blue: 1.0) : .secondary)
                        }
                    }
                    Button {
                        markUserInteraction()
                        showKeyboard.toggle()
                    } label: {
                        Image(systemName: showKeyboard ? "keyboard.fill" : "keyboard")
                    }
                }
            }
        }
        .overlay {
            if client.state == .sessionEnded {
                VStack(spacing: 16) {
                    Image(systemName: "terminal")
                        .font(.largeTitle)
                    Text("Session Ended")
                        .font(.headline)
                    Button("Back to Discovery") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.ultraThinMaterial)
            }
        }
        .onAppear {
            if keepScreenAwake {
                UIApplication.shared.isIdleTimerDisabled = true
            }
            setupClient()
            setupVoiceCommands()
            client.connect(url: target.websocketURL, key: target.encryptionKey)
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            client.disconnect()
            speechService.stopListening()
        }
        .onReceive(Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()) { _ in
            guard idleGlowEnabled else {
                if idleIntensity > 0 {
                    withAnimation(.easeOut(duration: 0.5)) { idleIntensity = 0 }
                }
                if speechService.isListening { speechService.stopListening() }
                return
            }
            let elapsed = Date().timeIntervalSince(lastActivityTime)
            if elapsed > idleGlowSeconds && idleIntensity == 0 && !waitingForOutput {
                withAnimation(.easeIn(duration: 0.8)) {
                    idleIntensity = 0.2
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    withAnimation(.easeIn(duration: 30)) {
                        idleIntensity = 1.0
                    }
                }
                startVoiceIfNeeded()
            }
            // If glow is active but listening stopped (linger expired), restart
            if idleIntensity > 0 && !waitingForOutput {
                startVoiceIfNeeded()
            }
        }
    }

    private var connectionStatusView: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(statusText)
                .font(.caption)
        }
    }

    private var statusColor: Color {
        switch client.state {
        case .connected: return .green
        case .connecting, .reconnecting: return .yellow
        case .disconnected, .sessionEnded: return .red
        }
    }

    private var statusText: String {
        switch client.state {
        case .connected: return "Connected"
        case .connecting: return "Connecting..."
        case .reconnecting(let attempt): return "Reconnecting (\(attempt))..."
        case .disconnected: return "Disconnected"
        case .sessionEnded: return "Session ended"
        }
    }

    private var isAtFitSize: Bool {
        let width = viewWidth > 0 ? viewWidth : UIScreen.main.bounds.width
        let targetCols = CellMetrics.colsForWidth(width, fontSize: CGFloat(fitFontSize))
        return grid.cols == targetCols
    }

    private func fitToPhone() {
        let width = viewWidth > 0 ? viewWidth : UIScreen.main.bounds.width
        let cols = CellMetrics.colsForWidth(width, fontSize: CGFloat(fitFontSize))
        let rows = grid.rows > 0 ? grid.rows : 24
        client.sendResize(cols: cols, rows: rows)
    }

    /// Called on terminal output — resets idle timer, allows glow to re-trigger later
    private func startVoiceIfNeeded() {
        guard voiceCommandsEnabled && !alwaysListening && SpeechCommandService.isAuthorized else { return }
        guard !speechService.isListening else { return }
        speechService.startListening(wakeWord: wakeWord, voiceTimeout: voiceTimeout, lingerTime: voiceLingerTime, allowServer: allowServerRecognition)
    }

    private func markTerminalActivity() {
        lastActivityTime = Date()
        waitingForOutput = false
        // Wake-word-activated or lingering voice stays through terminal output
        if speechService.activatedByWakeWord || speechService.isLingering { return }
        if idleIntensity > 0 {
            withAnimation(.easeOut(duration: 0.5)) {
                idleIntensity = 0
            }
        }
        if alwaysListening {
            speechService.deactivate()
        } else {
            speechService.stopListening()
        }
    }

    /// Called on user interaction — resets idle timer AND blocks glow until next terminal output
    private func markUserInteraction() {
        lastActivityTime = Date()
        waitingForOutput = true
        if idleIntensity > 0 {
            withAnimation(.easeOut(duration: 0.5)) {
                idleIntensity = 0
            }
        }
        if alwaysListening {
            speechService.deactivate()
        } else {
            speechService.stopListening()
        }
    }

    private func setupVoiceCommands() {
        speechService.onCommand = { [self] command in
            switch command {
            case .type(let text):
                client.sendInput(text)
            case .enter:
                client.sendInput("\r")
            case .tab:
                client.sendInput("\t")
            case .escape:
                client.sendInput("\u{1b}")
            case .space:
                client.sendInput(" ")
            case .delete(let count):
                for _ in 0..<count {
                    client.sendInput("\u{7f}")
                }
            case .arrowUp:
                client.sendInput("\u{1b}[A")
            case .arrowDown:
                client.sendInput("\u{1b}[B")
            case .arrowLeft:
                client.sendInput("\u{1b}[D")
            case .arrowRight:
                client.sendInput("\u{1b}[C")
            case .control(let letter):
                let upper = letter.uppercased()
                if let scalar = upper.unicodeScalars.first?.value, scalar >= 65, scalar <= 90 {
                    client.sendInput(String(UnicodeScalar(scalar - 64)!))
                }
            }
            lastActivityTime = Date()
            waitingForOutput = true
            // Fade glow after flash animation shows
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [self] in
                if !speechService.isActive {
                    withAnimation(.easeOut(duration: 0.5)) {
                        idleIntensity = 0
                    }
                }
            }
        }

        speechService.onActivate = { [self] in
            // Wake word detected — show the glow
            if idleIntensity == 0 {
                withAnimation(.easeIn(duration: 0.3)) {
                    idleIntensity = 0.5
                }
            }
        }

        speechService.onStop = { [self] in
            withAnimation(.easeOut(duration: 0.5)) {
                idleIntensity = 0
            }
            speechService.deactivate()
            if !alwaysListening {
                speechService.startLingering()
            }
            lastActivityTime = Date()
            waitingForOutput = true
        }

        speechService.onTimeout = { [self] in
            withAnimation(.easeOut(duration: 0.5)) {
                idleIntensity = 0
            }
            speechService.deactivate()
            if !alwaysListening {
                speechService.startLingering()
            }
            lastActivityTime = Date()
            waitingForOutput = true
        }

        // Always-listening: start immediately on connect
        if voiceCommandsEnabled && alwaysListening && SpeechCommandService.isAuthorized {
            speechService.startListening(wakeWord: wakeWord, voiceTimeout: voiceTimeout, lingerTime: voiceLingerTime, allowServer: allowServerRecognition)
        }
    }

    private func setupClient() {
        client.onMessage = { message in
            markTerminalActivity()
            switch message {
            case .state(let state):
                grid.applyState(state)
                // Auto-resize on first connection
                if autoResize && !hasAutoResized {
                    hasAutoResized = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        fitToPhone()
                    }
                }
            case .diff(let diff):
                grid.applyDiff(diff)
            case .scrollback(let sb):
                grid.appendScrollback(sb.lines)
            case .resize(let resize):
                grid.applyResize(resize)
            }
        }
    }
}

private struct BottomVisibleKey: PreferenceKey {
    static var defaultValue = true
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = nextValue()
    }
}
