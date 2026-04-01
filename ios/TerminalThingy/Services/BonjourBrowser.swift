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

    func start() {
        let descriptor = NWBrowser.Descriptor.bonjourWithTXTRecord(
            type: "_terminal-thingy._tcp",
            domain: "local."
        )
        let params = NWParameters()
        params.includePeerToPeer = true

        browser = NWBrowser(for: descriptor, using: params)
        browser?.browseResultsChangedHandler = { [weak self] results, _ in
            let sessions = results.compactMap { result -> DiscoveredSession? in
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
            // Deduplicate by deviceId — keep only the latest entry per device
            var seen: [String: DiscoveredSession] = [:]
            var deduped: [DiscoveredSession] = []
            for session in sessions {
                if session.deviceId.isEmpty {
                    // No deviceId — can't deduplicate, keep it
                    deduped.append(session)
                } else if seen[session.deviceId] == nil {
                    seen[session.deviceId] = session
                    deduped.append(session)
                }
                // else: duplicate deviceId, skip (stale entry)
            }

            DispatchQueue.main.async {
                self?.sessions = deduped
            }
        }
        browser?.start(queue: .global())
    }

    func stop() {
        browser?.cancel()
        browser = nil
    }
}

extension NWTXTRecord {
    func string(for key: String) -> String? {
        return self[key]
    }
}
