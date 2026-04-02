import Foundation
import Speech
import AVFoundation

enum VoiceCommand {
    case type(String)
    case enter
    case tab
    case escape
    case space
    case delete(Int)
    case arrowUp
    case arrowDown
    case arrowLeft
    case arrowRight
    case control(Character)
}

enum CommandResult {
    case accepted
    case ignored
}

class SpeechCommandService: ObservableObject {
    @Published var isListening = false
    @Published var isActive = false // glow + mic indicator visible
    @Published var activatedByWakeWord = false
    @Published var isLingering = false // still listening briefly after command
    @Published var lastHeard = ""
    @Published var commandResult: CommandResult?

    private func log(_ msg: String) {
        print("[Voice] \(msg)")
    }

    var onCommand: ((VoiceCommand) -> Void)?
    var onActivate: (() -> Void)?  // called when wake word triggers glow
    var onTimeout: (() -> Void)?   // called when voice timeout expires
    var onStop: (() -> Void)?      // called when user says "stop" or "exit"

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    private var wakeWord = "terminal"
    private var voiceTimeout: TimeInterval = 30
    private var lingerTime: TimeInterval = 10
    private var silenceTimer: Timer?
    private var timeoutTimer: Timer?
    private var lastPartialText = ""
    private var restartCount = 0
    private let maxRestarts = 3
    private var lingerTimer: Timer?

    private static let commandWords: Set<String> = [
        "type", "enter", "return", "tab", "escape", "space",
        "backspace", "delete", "up", "down", "left", "right",
        "control", "ctrl", "press", "stop", "exit"
    ]

    // MARK: - Permissions

    static func requestPermissions(completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { speechStatus in
            guard speechStatus == .authorized else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            AVAudioSession.sharedInstance().requestRecordPermission { micGranted in
                DispatchQueue.main.async { completion(micGranted) }
            }
        }
    }

    static var isAuthorized: Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    func isCommandWord(_ word: String) -> Bool {
        let w = word.lowercased()
        return w == wakeWord || Self.commandWords.contains(w)
    }

    func commandStartIndex(in words: [String]) -> Int {
        if words.first?.lowercased() == wakeWord { return 1 }
        return 0
    }

    // MARK: - Start / Stop

    func startListening(wakeWord: String, voiceTimeout: TimeInterval, lingerTime: TimeInterval = 10, allowServer: Bool) {
        guard !isListening else { log("startListening: already listening, skip"); return }
        guard speechRecognizer?.isAvailable == true else { log("startListening: recognizer not available"); return }
        log("startListening: wakeWord=\(wakeWord), timeout=\(voiceTimeout)s, allowServer=\(allowServer)")

        self.wakeWord = wakeWord.lowercased().trimmingCharacters(in: .whitespaces)
        self.voiceTimeout = voiceTimeout
        self.lingerTime = lingerTime
        self.useServerFallback = false
        self.allowServerFallback = allowServer
        self.restartCount = 0

        do {
            try ensureAudioEngine()
        } catch {
            return
        }

        startRecognitionTask()
        isListening = true
    }

    func stopListening() {
        log("stopListening")
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        stopAudioEngine()
        silenceTimer?.invalidate()
        silenceTimer = nil
        timeoutTimer?.invalidate()
        timeoutTimer = nil
        lingerTimer?.invalidate()
        lingerTimer = nil
        isListening = false
        isActive = false
        isLingering = false
        lastHeard = ""
        lastPartialText = ""
        commandResult = nil
    }

    /// Deactivate the glow/mic but keep listening for wake word
    func deactivate() {
        guard isActive else { return }
        log("deactivate (back to passive)")
        isActive = false
        activatedByWakeWord = false
        lastHeard = ""
        lastPartialText = ""
        commandResult = nil
        timeoutTimer?.invalidate()
        timeoutTimer = nil
    }

    /// Deactivate the mic indicator but start lingering so we keep listening briefly
    private func deactivateWithLinger() {
        guard isActive else { return }
        log("deactivate with linger")
        isActive = false
        activatedByWakeWord = false
        lastHeard = ""
        lastPartialText = ""
        timeoutTimer?.invalidate()
        timeoutTimer = nil
        startLingering()
    }

    /// Keep listening for 10 more seconds after a command, without glow
    func startLingering() {
        log("lingering: listening for \(Int(lingerTime))s more")
        isLingering = true
        lingerTimer?.invalidate()
        lingerTimer = Timer.scheduledTimer(withTimeInterval: lingerTime, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.log("linger expired, stopping")
                self.isLingering = false
                self.stopListening()
            }
        }
    }

    func stopLingering() {
        lingerTimer?.invalidate()
        lingerTimer = nil
        isLingering = false
    }

    private var audioEngineRunning = false
    private var useServerFallback = false
    private var allowServerFallback = false

    private func ensureAudioEngine() throws {
        guard !audioEngineRunning else { log("audioEngine: already running"); return }
        log("audioEngine: starting")

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
        audioEngineRunning = true
    }

    private func stopAudioEngine() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngineRunning = false
    }

    private func startRecognitionTask() {
        guard recognitionTask == nil else { log("recognitionTask: already running, skip"); return }
        log("recognitionTask: starting (onDevice=\(!useServerFallback))")

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let request = recognitionRequest else { return }

        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = !useServerFallback
        request.contextualStrings = buildContextualStrings()

        recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }

            if let result = result {
                let text = result.bestTranscription.formattedString.lowercased()
                self.restartCount = 0

                DispatchQueue.main.async {
                    self.log("partial: \"\(text)\" (isActive=\(self.isActive))")

                    if !self.isActive {
                        if self.textContainsWakeWord(text) {
                            self.log("wake word detected!")
                            self.isActive = true
                            self.activatedByWakeWord = true
                            self.stopLingering()
                            self.onActivate?()
                            self.startTimeoutTimer()
                            self.lastHeard = text
                        }
                    } else if self.isActive {
                        self.lastHeard = text
                    }

                    if text != self.lastPartialText {
                        self.lastPartialText = text
                        self.resetSilenceTimer()
                    }
                }
            }

            if let error = error {
                let nsError = error as NSError
                let isSilence = nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 1110
                    || error.localizedDescription.contains("No speech detected")

                if isSilence {
                    // Silence is normal — just restart, don't count as failure
                    if self.isListening {
                        self.restartRecognitionTask(delay: 0.1)
                    }
                } else {
                    self.log("recognitionTask error: \(error.localizedDescription) (restart #\(self.restartCount + 1))")
                    if self.isListening {
                        self.restartCount += 1
                        if self.restartCount <= self.maxRestarts {
                            let delay = Double(self.restartCount) * 1.0
                            self.restartRecognitionTask(delay: delay)
                        } else if self.allowServerFallback {
                            self.log("falling back to server recognition")
                            self.restartCount = 0
                            self.useServerFallback = true
                            self.restartRecognitionTask(delay: 1.0)
                        } else {
                            self.log("retries exhausted, no server fallback allowed")
                        }
                    }
                }
            }
        }
    }

    private func restartRecognitionTask(delay: Double = 0.1) {
        log("restartRecognitionTask (delay=\(delay)s)")
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        silenceTimer?.invalidate()
        silenceTimer = nil

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self, self.isListening else { return }
            self.startRecognitionTask()
        }
    }

    // MARK: - Silence Detection (workaround for isFinal never firing on-device)

    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            let text = self.lastPartialText
            guard !text.isEmpty else { return }

            self.log("silence detected, processing: \"\(text)\"")
            self.handleRecognizedText(text)
            self.lastPartialText = ""
            self.lastHeard = ""

            // Restart recognition task for next utterance (audio engine stays running)
            if self.isListening {
                self.restartRecognitionTask()
            }
        }
    }

    // MARK: - Timeout

    func startTimeoutTimer() {
        timeoutTimer?.invalidate()
        timeoutTimer = Timer.scheduledTimer(withTimeInterval: voiceTimeout, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.deactivate()
                self.onTimeout?()
            }
        }
    }

    /// Reset the timeout (called after a successful command so it doesn't expire mid-use)
    func resetTimeout() {
        if isActive {
            startTimeoutTimer()
        }
    }

    // MARK: - Contextual Strings

    private func buildContextualStrings() -> [String] {
        var strings = Array(Self.commandWords)
        let commonCtrl = ["a", "b", "c", "d", "e", "k", "l", "r", "u", "z"]
        for letter in commonCtrl {
            strings.append("ctrl \(letter)")
            strings.append("control \(letter)")
        }
        // "press X" phrases
        for cmd in ["enter", "return", "tab", "escape", "space", "backspace", "delete", "up", "down", "left", "right"] {
            strings.append("press \(cmd)")
        }
        // Common terminal words
        strings.append(contentsOf: [
            "claude", "git", "npm", "node", "python", "pip",
            "docker", "ssh", "sudo", "vim", "nano", "ls", "cd",
            "mkdir", "cat", "grep", "curl", "brew", "cargo", "make",
        ])
        if !wakeWord.isEmpty {
            strings.append(wakeWord)
            for cmd in Self.commandWords {
                strings.append("\(wakeWord) \(cmd)")
            }
        }
        return strings
    }

    // MARK: - Wake Word Detection

    private func textContainsWakeWord(_ text: String) -> Bool {
        let words = text.split(separator: " ").map { $0.lowercased() }
        return words.contains(wakeWord)
    }

    // MARK: - Command Parsing

    private func handleRecognizedText(_ text: String) {
        let raw = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }

        var words = raw.split(separator: " ").map(String.init)

        // Strip wake word if present
        if let wakeIndex = words.firstIndex(of: wakeWord) {
            words = Array(words.dropFirst(wakeIndex + 1))
        }

        // If not active yet (wake word mode, waiting for activation), ignore
        guard isActive else { return }
        guard !words.isEmpty else { return }

        // Strip optional "press" prefix
        if words.first == "press" {
            words.removeFirst()
            guard !words.isEmpty else { return }
        }

        guard let command = words.first else { return }
        let rest = Array(words.dropFirst())

        // Handle stop/exit
        if command == "stop" || command == "exit" {
            log("voice stop requested")
            DispatchQueue.main.async {
                self.commandResult = .accepted
                self.onStop?()
            }
            return
        }

        if let parsed = parseCommand(command: command, args: rest) {
            log("command accepted: \(command) \(rest)")
            DispatchQueue.main.async {
                self.commandResult = .accepted
                self.onCommand?(parsed)
                self.deactivateWithLinger()
            }
        } else {
            log("command ignored: \"\(command)\" args=\(rest)")
            DispatchQueue.main.async {
                self.commandResult = .ignored
                self.deactivateWithLinger()
            }
        }
    }

    private func parseCommand(command: String, args: [String]) -> VoiceCommand? {
        switch command {
        case "type":
            let text = args.joined(separator: " ")
            guard !text.isEmpty else { return nil }
            return .type(text)

        case "enter", "return":
            guard args.isEmpty else { return nil }
            return .enter

        case "tab":
            guard args.isEmpty else { return nil }
            return .tab

        case "escape":
            guard args.isEmpty else { return nil }
            return .escape

        case "space":
            guard args.isEmpty else { return nil }
            return .space

        case "delete", "backspace":
            if args.isEmpty { return .delete(1) }
            if args.count == 1, let n = parseNumber(args[0]), n > 0, n <= 50 {
                return .delete(n)
            }
            return nil

        case "up":
            guard args.isEmpty else { return nil }
            return .arrowUp
        case "down":
            guard args.isEmpty else { return nil }
            return .arrowDown
        case "left":
            guard args.isEmpty else { return nil }
            return .arrowLeft
        case "right":
            guard args.isEmpty else { return nil }
            return .arrowRight

        case "control", "ctrl":
            guard args.count == 1 else { return nil }
            guard let letter = parseLetter(args[0]) else { return nil }
            return .control(letter)

        default:
            return nil
        }
    }

    private func parseLetter(_ word: String) -> Character? {
        if word.count == 1, word.first?.isLetter == true {
            return Character(word.lowercased())
        }
        let letterMap: [String: Character] = [
            "a": "a", "ay": "a",
            "b": "b", "be": "b", "bee": "b",
            "c": "c", "see": "c", "sea": "c",
            "d": "d", "de": "d", "dee": "d",
            "e": "e",
            "f": "f", "ef": "f",
            "g": "g", "gee": "g",
            "h": "h",
            "i": "i", "eye": "i",
            "j": "j", "jay": "j",
            "k": "k", "kay": "k",
            "l": "l", "el": "l",
            "m": "m", "em": "m",
            "n": "n", "en": "n",
            "o": "o", "oh": "o",
            "p": "p", "pe": "p", "pee": "p",
            "q": "q", "queue": "q", "cue": "q",
            "r": "r", "are": "r", "ar": "r",
            "s": "s", "es": "s",
            "t": "t", "te": "t", "tea": "t",
            "u": "u", "you": "u",
            "v": "v",
            "w": "w", "double": "w",
            "x": "x", "ex": "x",
            "y": "y", "why": "y",
            "z": "z", "zee": "z", "zed": "z",
        ]
        return letterMap[word]
    }

    private func parseNumber(_ word: String) -> Int? {
        if let n = Int(word) { return n }
        let numberWords: [String: Int] = [
            "one": 1, "two": 2, "to": 2, "too": 2,
            "three": 3, "four": 4, "for": 4, "five": 5,
            "six": 6, "seven": 7, "eight": 8, "ate": 8,
            "nine": 9, "ten": 10, "eleven": 11, "twelve": 12,
            "thirteen": 13, "fourteen": 14, "fifteen": 15,
            "sixteen": 16, "seventeen": 17, "eighteen": 18,
            "nineteen": 19, "twenty": 20,
        ]
        return numberWords[word]
    }
}
