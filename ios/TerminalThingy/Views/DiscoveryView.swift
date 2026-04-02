import SwiftUI
import VisionKit
import CryptoKit

struct DiscoveryView: View {
    @StateObject private var browser = BonjourBrowser()
    @StateObject private var pairedStore = PairedDeviceStore()
    @State private var showQRScanner = false
    @State private var selectedSession: DiscoveredSession?
    @State private var connectionTarget: ConnectionTarget?
    @State private var showConnectionTarget = false
    @State private var showSettings = false

    private var knownSessions: [(DiscoveredSession, PairedDevice)] {
        browser.sessions.compactMap { session in
            guard !session.deviceId.isEmpty,
                  let device = pairedStore.device(for: session.deviceId) else { return nil }
            return (session, device)
        }
    }

    private var nearbySessions: [DiscoveredSession] {
        browser.sessions.filter { session in
            session.deviceId.isEmpty || pairedStore.device(for: session.deviceId) == nil
        }
    }

    var body: some View {
        List {
            if !knownSessions.isEmpty {
                Section("Known Devices") {
                    ForEach(knownSessions, id: \.0.id) { session, device in
                        Button {
                            connectionTarget = ConnectionTarget(
                                ip: session.ip,
                                port: session.port,
                                code: device.pin,
                                salt: device.salt,
                                deviceId: device.deviceId
                            )
                            showConnectionTarget = true
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(session.hostname)
                                        .font(.headline)
                                    Text(session.sessionName.isEmpty ? "port \(String(session.port))" : "\(session.sessionName) · port \(String(session.port))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                }
            }

            Section(knownSessions.isEmpty ? "Nearby" : "New Devices") {
                if nearbySessions.isEmpty && knownSessions.isEmpty {
                    HStack {
                        ProgressView()
                            .padding(.trailing, 8)
                        VStack(alignment: .leading) {
                            Text("Searching...")
                                .font(.headline)
                            Text("Looking for terminal-thingy sessions")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                ForEach(nearbySessions) { session in
                    Button {
                        selectedSession = session
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(session.hostname)
                                    .font(.headline)
                                HStack(spacing: 0) {
                                    if !session.sessionName.isEmpty {
                                        Text(session.sessionName)
                                            .lineLimit(1)
                                            .truncationMode(.tail)
                                            .layoutPriority(0)
                                        Text(" · ")
                                    }
                                    Text("\(session.shell) · port \(String(session.port))")
                                        .lineLimit(1)
                                        .layoutPriority(1)
                                }
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
        }
        .refreshable {
            browser.probeNow()
            try? await Task.sleep(nanoseconds: 2_500_000_000) // Wait for probes to complete
        }
        .navigationTitle("terminal-thingy")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                if DataScannerViewController.isSupported {
                    Button {
                        showQRScanner = true
                    } label: {
                        Image(systemName: "qrcode.viewfinder")
                    }
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showQRScanner) {
            QRScannerView { urlString in
                showQRScanner = false
                if let target = ConnectionTarget.fromURL(urlString) {
                    if let deviceId = target.deviceId, let code = target.code, let salt = target.salt {
                        pairedStore.pair(deviceId: deviceId, hostname: target.ip, pin: code, salt: salt)
                    }
                    connectionTarget = target
                    showConnectionTarget = true
                }
            }
        }
        .sheet(item: $selectedSession) { session in
            PINEntryView(session: session) { pin in
                if !session.deviceId.isEmpty {
                    pairedStore.pair(deviceId: session.deviceId, hostname: session.hostname, pin: pin, salt: session.salt)
                }
                connectionTarget = ConnectionTarget(
                    ip: session.ip,
                    port: session.port,
                    code: pin,
                    salt: session.salt,
                    deviceId: session.deviceId.isEmpty ? nil : session.deviceId
                )
                showConnectionTarget = true
            }
        }
        .navigationDestination(isPresented: $showConnectionTarget) {
            if let target = connectionTarget {
                TerminalView(target: target)
            }
        }
        .onAppear { browser.start() }
        .onDisappear { browser.stop() }
    }


}

struct ConnectionTarget: Hashable, Identifiable {
    var id: String { "\(ip):\(port)" }
    let ip: String
    let port: Int
    let code: String?
    let salt: String?
    let deviceId: String?

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
        let deviceId = components.queryItems?.first(where: { $0.name == "deviceId" })?.value

        return ConnectionTarget(ip: host, port: port, code: code, salt: salt, deviceId: deviceId)
    }
}
