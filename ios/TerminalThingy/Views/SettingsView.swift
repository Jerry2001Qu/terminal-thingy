import SwiftUI

struct SettingsView: View {
    @AppStorage("theme") private var theme: String = "dark"
    @AppStorage("keepScreenAwake") private var keepScreenAwake: Bool = true
    @AppStorage("fitFontSize") private var fitFontSize: Double = 10.0
    @AppStorage("idleGlowEnabled") private var idleGlowEnabled = true
    @AppStorage("idleGlowSeconds") private var idleGlowSeconds: Double = 30
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("Theme", selection: $theme) {
                        Text("Dark").tag("dark")
                        Text("Light").tag("light")
                        Text("System").tag("system")
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Fit-to-Phone Text Size")
                            Spacer()
                            Text("\(Int(fitFontSize))pt")
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $fitFontSize, in: 6...18, step: 1)
                    }
                    .padding(.vertical, 4)

                    let previewCols = CellMetrics.colsForWidth(UIScreen.main.bounds.width, fontSize: CGFloat(fitFontSize))
                    Text("~\(previewCols) columns on this device")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Terminal")
                } footer: {
                    Text("Controls how many columns \"Fit to Phone\" uses. Smaller text = more columns.")
                }

                Section {
                    Toggle("Idle Glow", isOn: $idleGlowEnabled)

                    if idleGlowEnabled {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Wait Time")
                                Spacer()
                                Text("\(Int(idleGlowSeconds))s")
                                    .foregroundStyle(.secondary)
                            }
                            Slider(value: $idleGlowSeconds, in: 5...120, step: 5)
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Idle Indicator")
                } footer: {
                    Text("Shows an orange glow around the screen when the terminal has been idle, indicating it may be waiting for input.")
                }

                Section("Display") {
                    Toggle("Keep Screen Awake", isOn: $keepScreenAwake)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
