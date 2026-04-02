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
    @State private var lastActivityTime = Date()
    @State private var idleIntensity: Double = 0
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
                        }
                    }
                    .onChange(of: grid.cells) { _ in
                        if isScrolledToBottom && grid.scrollbackLines.count > 0 {
                            withAnimation(.easeOut(duration: 0.1)) {
                                proxy.scrollTo("viewport", anchor: .bottom)
                            }
                        } else if !isScrolledToBottom {
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
                    .simultaneousGesture(
                        DragGesture().onChanged { _ in
                            isScrolledToBottom = false
                            markActivity()
                        }
                    )
                    .onTapGesture(count: 1) {
                        markActivity()
                    }
                    .onTapGesture(count: 2) {
                        markActivity()
                        showKeyboard.toggle()
                    }
                    .simultaneousGesture(
                        MagnificationGesture()
                            .onEnded { scale in
                                markActivity()
                                guard grid.cols > 0 else { return }
                                // scale > 1 = pinch out = bigger text = fewer cols
                                // scale < 1 = pinch in = smaller text = more cols
                                let newCols = max(Int(CGFloat(grid.cols) / scale), 20)
                                let rows = grid.rows > 0 ? grid.rows : 24
                                client.sendResize(cols: newCols, rows: rows)
                            }
                    )
                    .onChange(of: showKeyboard) { _ in
                        // When keyboard appears, scroll to bottom to keep cursor/prompt visible
                        // When keyboard disappears, scroll to top if no scrollback
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
            IdleGlowView(intensity: idleGlowEnabled ? idleIntensity : 0, pulsing: true)
                .allowsHitTesting(false)
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
                            fitToPhone()
                        } label: {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                        }
                    }
                    Button {
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
            client.connect(url: target.websocketURL, key: target.encryptionKey)
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            client.disconnect()
        }
        .onReceive(Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()) { _ in
            guard idleGlowEnabled else {
                if idleIntensity > 0 {
                    withAnimation(.easeOut(duration: 0.5)) { idleIntensity = 0 }
                }
                return
            }
            let elapsed = Date().timeIntervalSince(lastActivityTime)
            if elapsed > idleGlowSeconds && idleIntensity == 0 {
                withAnimation(.easeIn(duration: 0.8)) {
                    idleIntensity = 1.0
                }
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

    private func markActivity() {
        lastActivityTime = Date()
        if idleIntensity > 0 {
            // Quick animated fade-out
            withAnimation(.easeOut(duration: 0.5)) {
                idleIntensity = 0
            }
        }
    }

    private func setupClient() {
        client.onMessage = { message in
            markActivity()
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
