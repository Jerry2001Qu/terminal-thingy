import Foundation
import CryptoKit

enum ConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case reconnecting(attempt: Int)
    case sessionEnded
}

class WebSocketClient: NSObject, ObservableObject {
    @Published var state: ConnectionState = .disconnected

    private var task: URLSessionWebSocketTask?
    private var session: URLSession?
    private var url: URL?
    private var key: SymmetricKey?
    private var reconnectAttempt = 0
    private var maxReconnectDelay: TimeInterval = 30
    private var shouldReconnect = true

    var onMessage: ((ProtocolMessage) -> Void)?

    func connect(url: URL, key: SymmetricKey?) {
        self.url = url
        self.key = key
        self.shouldReconnect = true
        self.reconnectAttempt = 0
        doConnect()
    }

    private func doConnect() {
        guard let url = url else { return }

        DispatchQueue.main.async {
            self.state = self.reconnectAttempt == 0 ? .connecting : .reconnecting(attempt: self.reconnectAttempt)
        }

        session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        task = session?.webSocketTask(with: url)
        task?.resume()
    }

    private func receiveLoop() {
        task?.receive { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let message):
                self.handleRawMessage(message)
                self.receiveLoop()

            case .failure:
                self.handleDisconnect()
            }
        }
    }

    private func handleRawMessage(_ message: URLSessionWebSocketTask.Message) {
        let jsonData: Data?

        switch message {
        case .string(let text):
            if let key = key {
                // Encrypted — decrypt first
                jsonData = try? CryptoService.decrypt(base64Payload: text, key: key)
            } else {
                // Plain JSON
                jsonData = text.data(using: .utf8)
            }
        case .data(let data):
            jsonData = data
        @unknown default:
            return
        }

        guard let data = jsonData,
              let msg = try? JSONDecoder().decode(ProtocolMessage.self, from: data) else {
            return
        }

        DispatchQueue.main.async {
            self.onMessage?(msg)
        }
    }

    private func handleDisconnect() {
        guard shouldReconnect else {
            DispatchQueue.main.async { self.state = .sessionEnded }
            return
        }

        reconnectAttempt += 1
        let delay = min(pow(2.0, Double(reconnectAttempt)), maxReconnectDelay)

        DispatchQueue.main.async {
            self.state = .reconnecting(attempt: self.reconnectAttempt)
        }

        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.doConnect()
        }
    }

    func disconnect() {
        shouldReconnect = false
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
        session?.invalidateAndCancel()
        session = nil
        DispatchQueue.main.async { self.state = .disconnected }
    }
}

extension WebSocketClient: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession,
                    webSocketTask: URLSessionWebSocketTask,
                    didOpenWithProtocol protocol: String?) {
        reconnectAttempt = 0
        DispatchQueue.main.async { self.state = .connected }
        receiveLoop()
    }

    func urlSession(_ session: URLSession,
                    webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
                    reason: Data?) {
        handleDisconnect()
    }
}
