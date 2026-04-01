import SwiftUI
import VisionKit
import CryptoKit

struct DiscoveryView: View {
    @StateObject private var browser = BonjourBrowser()
    @State private var showQRScanner = false
    @State private var selectedSession: DiscoveredSession?
    @State private var connectionTarget: ConnectionTarget?

    private var showTerminal: Binding<Bool> {
        Binding(
            get: { connectionTarget != nil },
            set: { if !$0 { connectionTarget = nil } }
        )
    }

    var body: some View {
        List {
            if browser.sessions.isEmpty {
                VStack(spacing: 12) {
                    Label("Searching...", systemImage: "antenna.radiowaves.left.and.right")
                        .font(.headline)
                    Text("Looking for terminal-thingy sessions on your network")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .listRowBackground(Color.clear)
            }

            ForEach(browser.sessions) { session in
                Button {
                    selectedSession = session
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(session.hostname)
                                .font(.headline)
                            Text("\(session.shell) · port \(session.port)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Terminal Thingy")
        .navigationBarItems(trailing: qrButton)
        .sheet(isPresented: $showQRScanner) {
            QRScannerView { urlString in
                showQRScanner = false
                if let target = ConnectionTarget.fromURL(urlString) {
                    connectionTarget = target
                }
            }
        }
        .sheet(item: $selectedSession) { session in
            PINEntryView(session: session) { pin in
                connectionTarget = ConnectionTarget(
                    ip: session.ip,
                    port: session.port,
                    code: pin,
                    salt: session.salt
                )
            }
        }
        .navigationDestination(isPresented: showTerminal) {
            if let target = connectionTarget {
                TerminalView(target: target)
            }
        }
        .onAppear { browser.start() }
        .onDisappear { browser.stop() }
    }

    @ViewBuilder
    private var qrButton: some View {
        if DataScannerViewController.isSupported {
            Button {
                showQRScanner = true
            } label: {
                Image(systemName: "qrcode.viewfinder")
            }
        }
    }
}

struct ConnectionTarget: Hashable, Identifiable {
    var id: String { "\(ip):\(port)" }
    let ip: String
    let port: Int
    let code: String?
    let salt: String?

    var websocketURL: URL {
        var components = URLComponents()
        components.scheme = "ws"
        components.host = ip
        components.port = port
        if let code = code {
            components.queryItems = [URLQueryItem(name: "code", value: code)]
        }
        return components.url!
    }

    var encryptionKey: SymmetricKey? {
        guard let code = code, let salt = salt, !salt.isEmpty else { return nil }
        return CryptoService.deriveKey(code: code, saltHex: salt)
    }

    static func fromURL(_ urlString: String) -> ConnectionTarget? {
        guard let components = URLComponents(string: urlString),
              let host = components.host,
              let port = components.port else { return nil }

        let code = components.queryItems?.first(where: { $0.name == "code" })?.value
        let salt = components.queryItems?.first(where: { $0.name == "salt" })?.value

        return ConnectionTarget(ip: host, port: port, code: code, salt: salt)
    }
}
