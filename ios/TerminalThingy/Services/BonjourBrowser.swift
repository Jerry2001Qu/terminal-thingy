import Foundation
import Network

struct DiscoveredSession: Identifiable {
    let id = UUID()
    let name: String
    let hostname: String
    let shell: String
    let ip: String
    let port: Int
    let salt: String
    let deviceId: String
}

class BonjourBrowser: ObservableObject {
    @Published var sessions: [DiscoveredSession] = []
    private var browser: NWBrowser?
    private var lastCandidates: [DiscoveredSession] = []
    private var reprobeTimer: Timer?

    func start() {
        let descriptor = NWBrowser.Descriptor.bonjourWithTXTRecord(
            type: "_terminal-thingy._tcp",
            domain: "local."
        )
        let params = NWParameters()
        params.includePeerToPeer = true

        browser = NWBrowser(for: descriptor, using: params)
        browser?.browseResultsChangedHandler = { [weak self] results, _ in
            let candidates = results.compactMap { result -> DiscoveredSession? in
                guard case .bonjour(let record) = result.metadata else { return nil }

                let hostname = record.string(for: "hostname") ?? "Unknown"
                let shell = record.string(for: "shell") ?? "sh"
                let ip = record.string(for: "ip") ?? ""
                let portStr = record.string(for: "port") ?? "0"
                let salt = record.string(for: "salt") ?? ""
                let deviceId = record.string(for: "deviceId") ?? ""
                let port = Int(portStr) ?? 0

                guard !ip.isEmpty, port > 0 else { return nil }

                let name: String
                if case .service(let n, _, _, _) = result.endpoint {
                    name = n
                } else {
                    name = hostname
                }

                return DiscoveredSession(
                    name: name,
                    hostname: hostname,
                    shell: shell,
                    ip: ip,
                    port: port,
                    salt: salt,
                    deviceId: deviceId
                )
            }

            // Deduplicate by deviceId
            var seen: [String: DiscoveredSession] = [:]
            var deduped: [DiscoveredSession] = []
            for session in candidates {
                if session.deviceId.isEmpty {
                    deduped.append(session)
                } else if seen[session.deviceId] == nil {
                    seen[session.deviceId] = session
                    deduped.append(session)
                }
            }

            DispatchQueue.main.async {
                self?.lastCandidates = deduped
                // Show all candidates immediately so the list isn't empty
                self?.sessions = deduped
            }
            // Then filter out dead ones in the background
            self?.probeAndRemoveDead(deduped)
        }
        browser?.start(queue: .global())

        // Re-probe every 5 seconds to remove dead sessions
        reprobeTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            guard let self = self, !self.lastCandidates.isEmpty else { return }
            self.probeAndRemoveDead(self.lastCandidates)
        }
    }

    /// Probe each candidate. Remove unreachable ones from the published sessions list.
    private func probeAndRemoveDead(_ candidates: [DiscoveredSession]) {
        for session in candidates {
            let endpoint = NWEndpoint.hostPort(
                host: NWEndpoint.Host(session.ip),
                port: NWEndpoint.Port(integerLiteral: UInt16(session.port))
            )
            let connection = NWConnection(to: endpoint, using: .tcp)
            var resolved = false

            connection.stateUpdateHandler = { [weak self] state in
                guard !resolved else { return }
                switch state {
                case .ready:
                    // Alive — keep it in the list (it's already there)
                    resolved = true
                    connection.cancel()
                case .failed:
                    // Dead — remove from list
                    resolved = true
                    connection.cancel()
                    DispatchQueue.main.async {
                        self?.sessions.removeAll { $0.ip == session.ip && $0.port == session.port }
                    }
                default:
                    break
                }
            }

            connection.start(queue: .global())

            // Timeout — if no response in 2s, assume dead
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [weak self] in
                guard !resolved else { return }
                resolved = true
                connection.cancel()
                DispatchQueue.main.async {
                    self?.sessions.removeAll { $0.ip == session.ip && $0.port == session.port }
                }
            }
        }
    }

    func probeNow() {
        guard !lastCandidates.isEmpty else { return }
        sessions = lastCandidates
        probeAndRemoveDead(lastCandidates)
    }

    func stop() {
        reprobeTimer?.invalidate()
        reprobeTimer = nil
        browser?.cancel()
        browser = nil
        lastCandidates.removeAll()
    }
}

extension NWTXTRecord {
    func string(for key: String) -> String? {
        return self[key]
    }
}
