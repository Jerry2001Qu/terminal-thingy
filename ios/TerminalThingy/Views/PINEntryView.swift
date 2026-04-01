import SwiftUI

struct PINEntryView: View {
    let session: DiscoveredSession
    let onSubmit: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var pin = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Enter PIN for \(session.hostname)")
                    .font(.headline)

                Text("Check the terminal on your computer for the 6-digit PIN")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                TextField("000 000", text: $pin)
                    .font(.system(size: 32, design: .monospaced))
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .focused($focused)
                    .onChange(of: pin) { newValue in
                        let digits = newValue.filter(\.isNumber)
                        if digits.count > 6 {
                            pin = String(digits.prefix(6))
                        } else {
                            pin = digits
                        }
                    }

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
}
