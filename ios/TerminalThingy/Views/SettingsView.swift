import SwiftUI

struct SettingsView: View {
    @AppStorage("theme") private var theme: String = "dark"
    @AppStorage("keepScreenAwake") private var keepScreenAwake: Bool = true
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
