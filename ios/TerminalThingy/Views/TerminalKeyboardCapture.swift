import SwiftUI
import UIKit

// MARK: - SwiftUI wrapper

struct TerminalKeyboardCapture: UIViewRepresentable {
    let onKey: (String) -> Void
    let onHideKeyboard: () -> Void

    func makeUIView(context: Context) -> TerminalInputView {
        let view = TerminalInputView()
        view.onKey = onKey
        view.onHideKeyboard = onHideKeyboard
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            view.becomeFirstResponder()
        }
        return view
    }

    func updateUIView(_ view: TerminalInputView, context: Context) {
        view.onKey = onKey
        view.onHideKeyboard = onHideKeyboard
    }
}

// MARK: - UIView that accepts keyboard input

class TerminalInputView: UIView, UIKeyInput {
    var onKey: ((String) -> Void)?
    var onHideKeyboard: (() -> Void)?
    var ctrlActive = false
    private var shiftHeld = false
    private var deleteTimer: Timer?
    private var deleteCount = 0

    // MARK: First responder

    override var canBecomeFirstResponder: Bool { true }

    @discardableResult
    override func resignFirstResponder() -> Bool {
        stopDeleteRepeat()
        return super.resignFirstResponder()
    }

    // MARK: Input accessory view

    private lazy var accessoryBar: TerminalAccessoryBar = {
        let bar = TerminalAccessoryBar(frame: CGRect(x: 0, y: 0,
                                                     width: UIScreen.main.bounds.width,
                                                     height: 44))
        bar.onKey = { [weak self] key in self?.handleSpecialKey(key) }
        bar.onCtrlToggle = { [weak self] active in self?.ctrlActive = active }
        bar.onHideKeyboard = { [weak self] in
            self?.resignFirstResponder()
            self?.onHideKeyboard?()
        }
        return bar
    }()

    override var inputAccessoryView: UIView? { accessoryBar }

    // MARK: Track Shift key

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses {
            if press.key?.keyCode == .keyboardLeftShift || press.key?.keyCode == .keyboardRightShift {
                shiftHeld = true
            }
        }
        super.pressesBegan(presses, with: event)
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses {
            if press.key?.keyCode == .keyboardLeftShift || press.key?.keyCode == .keyboardRightShift {
                shiftHeld = false
            }
        }
        super.pressesEnded(presses, with: event)
    }

    // MARK: UIKeyInput

    var hasText: Bool { true }

    func insertText(_ text: String) {
        stopDeleteRepeat()
        // Enter sends \r (carriage return = submit in Claude Code)
        // Shift+Enter sends \n (line feed = newline in Claude Code)
        let terminalText: String
        if text == "\n" {
            terminalText = shiftHeld ? "\n" : "\r"
        } else {
            terminalText = text
        }
        if ctrlActive {
            for char in terminalText {
                let upper = char.uppercased()
                if let scalar = upper.unicodeScalars.first?.value, scalar >= 64, scalar <= 95 {
                    onKey?(String(UnicodeScalar(scalar - 64)!))
                } else if char == "\r" {
                    onKey?("\r")
                } else {
                    onKey?(String(char))
                }
            }
            ctrlActive = false
            accessoryBar.setCtrlActive(false)
        } else {
            onKey?(terminalText)
        }
    }

    func deleteBackward() {
        onKey?("\u{7f}")
        // Start repeat timer on first delete
        deleteCount += 1
        if deleteCount == 1 {
            // After initial delay, start repeating
            deleteTimer?.invalidate()
            deleteTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
                self?.deleteTimer = Timer.scheduledTimer(withTimeInterval: 0.07, repeats: true) { [weak self] _ in
                    self?.onKey?("\u{7f}")
                }
            }
        }
    }

    // Called when the delete key is released (text changes stop)
    // We reset via insertText or the next interaction
    private func stopDeleteRepeat() {
        deleteTimer?.invalidate()
        deleteTimer = nil
        deleteCount = 0
    }

    // MARK: Special keys from accessory bar

    private func handleSpecialKey(_ key: String) {
        if ctrlActive && key.count == 1 {
            let upper = key.uppercased()
            if let scalar = upper.unicodeScalars.first?.value, scalar >= 64, scalar <= 95 {
                onKey?(String(UnicodeScalar(scalar - 64)!))
                ctrlActive = false
                accessoryBar.setCtrlActive(false)
                return
            }
        }
        onKey?(key)
    }

    // MARK: UITextInputTraits (suppress autocorrect etc.)

    var autocorrectionType: UITextAutocorrectionType { .no }
    var autocapitalizationType: UITextAutocapitalizationType { .none }
    var smartQuotesType: UITextSmartQuotesType { .no }
    var smartDashesType: UITextSmartDashesType { .no }
    var smartInsertDeleteType: UITextSmartInsertDeleteType { .no }
    var spellCheckingType: UITextSpellCheckingType { .no }
    var keyboardAppearance: UIKeyboardAppearance { .dark }
    var returnKeyType: UIReturnKeyType { .default }
    var enablesReturnKeyAutomatically: Bool { false }
}

// MARK: - UIKit accessory bar

class TerminalAccessoryBar: UIView {
    var onKey: ((String) -> Void)?
    var onCtrlToggle: ((Bool) -> Void)?
    var onHideKeyboard: (() -> Void)?

    private var ctrlButton: UIButton!
    private var ctrlActive = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupBar()
    }

    required init?(coder: NSCoder) { fatalError() }

    func setCtrlActive(_ active: Bool) {
        ctrlActive = active
        ctrlButton.backgroundColor = active ? .white : .systemGray3
        ctrlButton.setTitleColor(active ? .black : .white, for: .normal)
    }

    private func setupBar() {
        backgroundColor = .systemGray5

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])

        // Tab
        stack.addArrangedSubview(makeKey("Tab") { [weak self] in self?.onKey?("\t") })

        // Ctrl (sticky)
        ctrlButton = makeKey("Ctrl") { [weak self] in
            guard let self = self else { return }
            self.ctrlActive.toggle()
            self.setCtrlActive(self.ctrlActive)
            self.onCtrlToggle?(self.ctrlActive)
        }
        stack.addArrangedSubview(ctrlButton)

        // Esc
        stack.addArrangedSubview(makeKey("Esc") { [weak self] in self?.onKey?("\u{1b}") })

        // Arrow pad
        stack.addArrangedSubview(makeArrowPad())

        // Pipe
        stack.addArrangedSubview(makeKey("|") { [weak self] in self?.onKey?("|") })

        // Tilde
        stack.addArrangedSubview(makeKey("~") { [weak self] in self?.onKey?("~") })

        // Flexible spacer
        let spacer = UIView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        stack.addArrangedSubview(spacer)

        // Hide keyboard button
        let hideBtn = UIButton(type: .system)
        hideBtn.setImage(UIImage(systemName: "keyboard.chevron.compact.down"), for: .normal)
        hideBtn.tintColor = .white
        hideBtn.addAction(UIAction { [weak self] _ in self?.onHideKeyboard?() }, for: .touchUpInside)
        stack.addArrangedSubview(hideBtn)
    }

    private func makeKey(_ title: String, action: @escaping () -> Void) -> UIButton {
        let btn = UIButton(type: .system)
        btn.setTitle(title, for: .normal)
        btn.titleLabel?.font = .monospacedSystemFont(ofSize: 14, weight: .medium)
        btn.setTitleColor(.white, for: .normal)
        btn.backgroundColor = .systemGray3
        btn.layer.cornerRadius = 6
        btn.contentEdgeInsets = UIEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
        btn.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return btn
    }

    private func makeArrowPad() -> UIView {
        let container = UIView()
        container.backgroundColor = .systemGray3
        container.layer.cornerRadius = 6

        let label = UILabel()
        label.text = "< >"
        label.font = .monospacedSystemFont(ofSize: 14, weight: .medium)
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            container.widthAnchor.constraint(equalToConstant: 60),
            container.heightAnchor.constraint(equalToConstant: 32),
        ])

        // Swipe gestures
        let directions: [(UISwipeGestureRecognizer.Direction, String)] = [
            (.up, "\u{1b}[A"),
            (.down, "\u{1b}[B"),
            (.left, "\u{1b}[D"),
            (.right, "\u{1b}[C"),
        ]
        for (direction, _) in directions {
            let swipe = UISwipeGestureRecognizer(target: self, action: #selector(handleArrowSwipe(_:)))
            swipe.direction = direction
            container.addGestureRecognizer(swipe)
        }

        // Tap = up arrow (most common use: history scroll)
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleArrowTap))
        container.addGestureRecognizer(tap)

        return container
    }

    @objc private func handleArrowSwipe(_ gesture: UISwipeGestureRecognizer) {
        switch gesture.direction {
        case .up:    onKey?("\u{1b}[A")
        case .down:  onKey?("\u{1b}[B")
        case .left:  onKey?("\u{1b}[D")
        case .right: onKey?("\u{1b}[C")
        default: break
        }
    }

    @objc private func handleArrowTap() {
        onKey?("\u{1b}[A")
    }
}
