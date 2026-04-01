import SwiftUI

struct PINEntryView: View {
    let session: DiscoveredSession
    let onSubmit: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var pin = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Text("Enter PIN for \(session.hostname)")
                    .font(.headline)

                Text("Check the terminal on your computer for the 6-digit PIN")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                // 6-digit code display with individual boxes
                ZStack {
                    // Hidden TextField for keyboard input
                    TextField("", text: $pin)
                        .keyboardType(.numberPad)
                        .focused($focused)
                        .foregroundColor(.clear)
                        .accentColor(.clear)
                        .frame(width: 1, height: 1)
                        .onChange(of: pin) { newValue in
                            let digits = newValue.filter(\.isNumber)
                            if digits.count > 6 {
                                pin = String(digits.prefix(6))
                            } else if digits != newValue {
                                pin = digits
                            }
                            // Auto-submit when 6 digits entered
                            if pin.count == 6 {
                                onSubmit(pin)
                                dismiss()
                            }
                        }

                    // Visual digit boxes
                    HStack(spacing: 8) {
                        ForEach(0..<6, id: \.self) { index in
                            digitBox(at: index)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { focused = true }
                }

                // Spacer between groups of 3 is handled by extra spacing
                // at index 2-3 boundary in digitBox

                Button("Connect") {
                    guard pin.count == 6 else { return }
                    onSubmit(pin)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(pin.count != 6)
            }
            .padding()
            .navigationTitle("Enter PIN")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(leading: Button("Cancel") { dismiss() })
            .onAppear { focused = true }
        }
    }

    @ViewBuilder
    private func digitBox(at index: Int) -> some View {
        let hasDigit = index < pin.count
        let digit = hasDigit ? String(pin[pin.index(pin.startIndex, offsetBy: index)]) : ""
        let isCursor = index == pin.count

        // Add extra spacing between digit 3 and 4 (the gap in "123 456")
        if index == 3 {
            Spacer().frame(width: 8)
        }

        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .stroke(isCursor ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: isCursor ? 2 : 1)
                .frame(width: 44, height: 56)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(.systemGray6))
                )

            if hasDigit {
                Text(digit)
                    .font(.system(size: 28, weight: .semibold, design: .monospaced))
            } else {
                Text(String(index < 3 ? index + 1 : index - 2))
                    .font(.system(size: 28, weight: .regular, design: .monospaced))
                    .foregroundStyle(.quaternary)
            }
        }
    }
}
