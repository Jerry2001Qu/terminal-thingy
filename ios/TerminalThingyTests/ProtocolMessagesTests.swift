import XCTest
@testable import TerminalThingy

final class ProtocolMessagesTests: XCTestCase {

    func testDecodeStateMessage() throws {
        let json = """
        {
            "type": "state",
            "cols": 80,
            "rows": 24,
            "cells": [[{"char": "h", "fg": "#fff", "bg": null, "bold": false, "italic": false, "underline": false}]],
            "cursorX": 1,
            "cursorY": 0
        }
        """.data(using: .utf8)!

        let message = try JSONDecoder().decode(ProtocolMessage.self, from: json)
        if case .state(let state) = message {
            XCTAssertEqual(state.cols, 80)
            XCTAssertEqual(state.rows, 24)
            XCTAssertEqual(state.cells[0][0].char, "h")
            XCTAssertEqual(state.cells[0][0].fg, "#fff")
            XCTAssertNil(state.cells[0][0].bg)
            XCTAssertFalse(state.cells[0][0].bold)
            XCTAssertEqual(state.cursorX, 1)
        } else {
            XCTFail("Expected state message")
        }
    }

    func testDecodeDiffMessage() throws {
        let json = """
        {
            "type": "diff",
            "changes": [{"row": 0, "col": 0, "cells": [{"char": "$", "fg": "#0f0", "bg": null, "bold": false, "italic": false, "underline": false}]}],
            "cursorX": 2,
            "cursorY": 0
        }
        """.data(using: .utf8)!

        let message = try JSONDecoder().decode(ProtocolMessage.self, from: json)
        if case .diff(let diff) = message {
            XCTAssertEqual(diff.changes.count, 1)
            XCTAssertEqual(diff.changes[0].row, 0)
            XCTAssertEqual(diff.changes[0].cells[0].char, "$")
            XCTAssertEqual(diff.cursorX, 2)
        } else {
            XCTFail("Expected diff message")
        }
    }

    func testDecodeScrollbackMessage() throws {
        let json = """
        {
            "type": "scrollback",
            "lines": [[{"char": "x", "fg": null, "bg": null, "bold": false, "italic": false, "underline": false}]]
        }
        """.data(using: .utf8)!

        let message = try JSONDecoder().decode(ProtocolMessage.self, from: json)
        if case .scrollback(let sb) = message {
            XCTAssertEqual(sb.lines.count, 1)
            XCTAssertEqual(sb.lines[0][0].char, "x")
        } else {
            XCTFail("Expected scrollback message")
        }
    }

    func testDecodeResizeMessage() throws {
        let json = """
        {"type": "resize", "cols": 120, "rows": 40}
        """.data(using: .utf8)!

        let message = try JSONDecoder().decode(ProtocolMessage.self, from: json)
        if case .resize(let r) = message {
            XCTAssertEqual(r.cols, 120)
            XCTAssertEqual(r.rows, 40)
        } else {
            XCTFail("Expected resize message")
        }
    }
}
