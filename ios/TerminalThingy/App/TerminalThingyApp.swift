import SwiftUI

@main
struct TerminalThingyApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                DiscoveryView()
            }
            .preferredColorScheme(.dark)
        }
    }
}
