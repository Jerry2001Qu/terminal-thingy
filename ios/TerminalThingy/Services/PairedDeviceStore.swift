import Foundation

struct PairedDevice: Codable, Identifiable, Equatable {
    let deviceId: String
    var hostname: String
    var pin: String
    var salt: String
    var lastSeen: Date

    var id: String { deviceId }
}

class PairedDeviceStore: ObservableObject {
    @Published private(set) var devices: [PairedDevice] = []

    private let key = "terminal-thingy-paired-devices"

    init() {
        load()
    }

    func pair(deviceId: String, hostname: String, pin: String, salt: String) {
        if let index = devices.firstIndex(where: { $0.deviceId == deviceId }) {
            devices[index].hostname = hostname
            devices[index].pin = pin
            devices[index].salt = salt
            devices[index].lastSeen = Date()
        } else {
            devices.append(PairedDevice(
                deviceId: deviceId,
                hostname: hostname,
                pin: pin,
                salt: salt,
                lastSeen: Date()
            ))
        }
        save()
    }

    func device(for deviceId: String) -> PairedDevice? {
        devices.first { $0.deviceId == deviceId }
    }

    func forget(_ deviceId: String) {
        devices.removeAll { $0.deviceId == deviceId }
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([PairedDevice].self, from: data) else {
            devices = []
            return
        }
        devices = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(devices) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
