import SwiftUI
import Speech

struct SettingsView: View {
    @AppStorage("theme") private var theme: String = "dark"
    @AppStorage("keepScreenAwake") private var keepScreenAwake: Bool = true
    @AppStorage("fitFontSize") private var fitFontSize: Double = 10.0
    @AppStorage("autoResize") private var autoResize = true
    @AppStorage("idleGlowEnabled") private var idleGlowEnabled = true
    @AppStorage("idleGlowSeconds") private var idleGlowSeconds: Double = 8
    @AppStorage("voiceCommandsEnabled") private var voiceCommandsEnabled = false
    @AppStorage("alwaysListening") private var alwaysListening = false
    @AppStorage("wakeWord") private var wakeWord = "terminal"
    @AppStorage("voiceTimeout") private var voiceTimeout: Double = 30
    @AppStorage("voiceLingerTime") private var voiceLingerTime: Double = 10
    @AppStorage("allowServerRecognition") private var allowServerRecognition = false
    @State private var showPermissionDenied = false
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
                    Toggle("Auto-Resize", isOn: $autoResize)
                } header: {
                    Text("Terminal")
                } footer: {
                    Text("Text size controls \"Fit to Phone\" columns. Auto-resize adjusts the terminal on connect and rotation.")
                }

                Section {
                    Toggle("Idle Glow", isOn: $idleGlowEnabled)

                    if idleGlowEnabled {
                        HStack {
                            Text("Wait Time")
                            Spacer()
                            Stepper("\(Int(idleGlowSeconds))s", value: $idleGlowSeconds, in: 1...120, step: 1)
                                .fixedSize()
                        }
                    }
                    Toggle("Voice Commands", isOn: Binding(
                        get: { voiceCommandsEnabled },
                        set: { newValue in
                            if newValue {
                                SpeechCommandService.requestPermissions { granted in
                                    if granted {
                                        voiceCommandsEnabled = true
                                    } else {
                                        showPermissionDenied = true
                                    }
                                }
                            } else {
                                voiceCommandsEnabled = false
                            }
                        }
                    ))

                    if voiceCommandsEnabled {
                        HStack {
                            Text("Wake Word")
                            Spacer()
                            TextField("terminal", text: $wakeWord)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 150)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        }
                        Toggle("Always Listening", isOn: $alwaysListening)
                        if !alwaysListening {
                            HStack {
                                Text("Linger Time")
                                Spacer()
                                Stepper("\(Int(voiceLingerTime))s", value: $voiceLingerTime, in: 5...60, step: 5)
                                    .fixedSize()
                            }
                        }
                        HStack {
                            Text("Voice Timeout")
                            Spacer()
                            Stepper("\(Int(voiceTimeout))s", value: $voiceTimeout, in: 10...120, step: 5)
                                .fixedSize()
                        }
                        Toggle("Allow Cloud Recognition", isOn: $allowServerRecognition)
                    }
                } header: {
                    Text("Idle Indicator")
                } footer: {
                    if voiceCommandsEnabled && alwaysListening {
                        Text("Always listens for \"\(wakeWord)\". Say \"\(wakeWord) enter\" or \"\(wakeWord) type hello\" anytime to send commands.\(allowServerRecognition ? " Cloud recognition sends audio to Apple." : " Recognition runs on-device only.")")
                    } else if voiceCommandsEnabled {
                        Text("Listens for \"\(wakeWord)\" while terminal is idle. Say \"\(wakeWord) enter\" or \"\(wakeWord) type hello\" to send commands.\(allowServerRecognition ? " Cloud recognition sends audio to Apple." : " Recognition runs on-device only.")")
                    } else {
                        Text("Shows a blue glow around the screen when the terminal has been idle, indicating it may be waiting for input.")
                    }
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
            .alert("Permission Required", isPresented: $showPermissionDenied) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Voice commands require microphone and speech recognition access. Enable them in Settings.")
            }
        }
    }
}
