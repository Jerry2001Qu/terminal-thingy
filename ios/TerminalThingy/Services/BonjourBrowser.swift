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
    private var probeGeneration = 0
    private let probeQueue = DispatchQueue(label: "terminal-thingy.probe")

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

            self?.lastCandidates = deduped
            self?.probeAndFilter(deduped)
        }
        browser?.start(queue: .global())

        // Re-probe every 5 seconds to catch dead sessions
        reprobeTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            guard let self = self, !self.lastCandidates.isEmpty else { return }
            self.probeAndFilter(self.lastCandidates)
        }
    }

    private func probeAndFilter(_ candidates: [DiscoveredSession]) {
        // Increment generation — results from older probes will be ignored
        probeQueue.sync { probeGeneration += 1 }
        let currentGen = probeGeneration

        guard !candidates.isEmpty else {
            DispatchQueue.main.async { self.sessions = [] }
            return
        }

        let group = DispatchGroup()
        var reachable: [DiscoveredSession] = []

        for session in candidates {
            group.enter()
            let endpoint = NWEndpoint.hostPort(
                host: NWEndpoint.Host(session.ip),
                port: NWEndpoint.Port(integerLiteral: UInt16(session.port))
            )
            let connection = NWConnection(to: endpoint, using: .tcp)
            var didLeave = false

            connection.stateUpdateHandler = { [weak self] state in
                guard let self = self else { return }
                switch state {
                case .ready:
                    self.probeQueue.sync {
                        if !didLeave {
                            reachable.append(session)
                            didLeave = true
                            group.leave()
                        }
                    }
                    connection.cancel()
                case .failed, .cancelled:
                    self.probeQueue.sync {
                        if !didLeave {
                            didLeave = true
                            group.leave()
                        }
                    }
                default:
                    break
                }
            }

            connection.start(queue: .global())

            // Timeout
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.probeQueue.sync {
                    if !didLeave {
                        didLeave = true
                        group.leave()
                    }
                }
                connection.cancel()
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            // Only apply results if this is still the latest probe batch
            guard self.probeGeneration == currentGen else { return }
            self.sessions = reachable
        }
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
