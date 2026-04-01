import SwiftUI

struct TerminalView: View {
    let target: ConnectionTarget

    var body: some View {
        Text("Terminal View - \(target.ip):\(target.port)")
    }
}
