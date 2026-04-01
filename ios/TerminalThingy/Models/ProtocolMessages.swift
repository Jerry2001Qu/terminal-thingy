import Foundation

struct TerminalCell: Codable, Equatable {
    let char: String
    let fg: String?
    let bg: String?
    let bold: Bool
    let italic: Bool
    let underline: Bool
}

struct StateMessage: Codable {
    let type: String
    let cols: Int
    let rows: Int
    let cells: [[TerminalCell]]
    let cursorX: Int
    let cursorY: Int
}

struct DiffChange: Codable {
    let row: Int
    let col: Int
    let cells: [TerminalCell]
}

struct DiffMessage: Codable {
    let type: String
    let changes: [DiffChange]
    let cursorX: Int
    let cursorY: Int
}

struct ScrollbackMessage: Codable {
    let type: String
    let lines: [[TerminalCell]]
}

struct ResizeMessage: Codable {
    let type: String
    let cols: Int
    let rows: Int
}

enum ProtocolMessage: Decodable {
    case state(StateMessage)
    case diff(DiffMessage)
    case scrollback(ScrollbackMessage)
    case resize(ResizeMessage)

    private enum CodingKeys: String, CodingKey {
        case type
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "state":
            self = .state(try StateMessage(from: decoder))
        case "diff":
            self = .diff(try DiffMessage(from: decoder))
        case "scrollback":
            self = .scrollback(try ScrollbackMessage(from: decoder))
        case "resize":
            self = .resize(try ResizeMessage(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: container,
                debugDescription: "Unknown message type: \(type)"
            )
        }
    }
}
