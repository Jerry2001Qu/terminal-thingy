import SwiftUI

@main
struct TerminalThingyApp: App {
    @AppStorage("theme") private var theme: String = "dark"

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                DiscoveryView()
            }
            .preferredColorScheme(theme == "dark" ? .dark : theme == "light" ? .light : nil)
        }
    }
}
