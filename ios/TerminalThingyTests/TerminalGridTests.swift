import XCTest
@testable import TerminalThingy

final class TerminalGridTests: XCTestCase {

    func testApplyState() {
        let grid = TerminalGrid()
        let cell = TerminalCell(char: "A", fg: "#fff", bg: nil, bold: false, italic: false, underline: false)
        let state = StateMessage(type: "state", cols: 2, rows: 1, cells: [[cell, cell]], cursorX: 1, cursorY: 0)

        grid.applyState(state)

        XCTAssertEqual(grid.cols, 2)
        XCTAssertEqual(grid.rows, 1)
        XCTAssertEqual(grid.cells.count, 1)
        XCTAssertEqual(grid.cells[0].count, 2)
        XCTAssertEqual(grid.cells[0][0].char, "A")
        XCTAssertEqual(grid.cursorX, 1)
    }

    func testApplyDiff() {
        let grid = TerminalGrid()
        let cellA = TerminalCell(char: "A", fg: nil, bg: nil, bold: false, italic: false, underline: false)
        let cellB = TerminalCell(char: "B", fg: nil, bg: nil, bold: false, italic: false, underline: false)
        let state = StateMessage(type: "state", cols: 2, rows: 2, cells: [[cellA, cellA], [cellA, cellA]], cursorX: 0, cursorY: 0)
        grid.applyState(state)

        let diff = DiffMessage(type: "diff", changes: [DiffChange(row: 1, col: 0, cells: [cellB, cellB])], cursorX: 1, cursorY: 1)
        grid.applyDiff(diff)

        XCTAssertEqual(grid.cells[0][0].char, "A")
        XCTAssertEqual(grid.cells[1][0].char, "B")
        XCTAssertEqual(grid.cursorX, 1)
        XCTAssertEqual(grid.cursorY, 1)
    }

    func testAppendScrollback() {
        let grid = TerminalGrid()
        let cell = TerminalCell(char: "X", fg: nil, bg: nil, bold: false, italic: false, underline: false)

        grid.appendScrollback([[cell, cell]])
        grid.appendScrollback([[cell]])

        XCTAssertEqual(grid.scrollbackLines.count, 2)
        XCTAssertEqual(grid.scrollbackLines[0].count, 2)
        XCTAssertEqual(grid.scrollbackLines[1].count, 1)
    }

    func testApplyResize() {
        let grid = TerminalGrid()
        let resize = ResizeMessage(type: "resize", cols: 120, rows: 40)
        grid.applyResize(resize)

        XCTAssertEqual(grid.cols, 120)
        XCTAssertEqual(grid.rows, 40)
    }

    func testDiffIgnoresOutOfBoundsRow() {
        let grid = TerminalGrid()
        let cell = TerminalCell(char: "A", fg: nil, bg: nil, bold: false, italic: false, underline: false)
        let state = StateMessage(type: "state", cols: 1, rows: 1, cells: [[cell]], cursorX: 0, cursorY: 0)
        grid.applyState(state)

        let diff = DiffMessage(type: "diff", changes: [DiffChange(row: 5, col: 0, cells: [cell])], cursorX: 0, cursorY: 0)
        grid.applyDiff(diff)

        XCTAssertEqual(grid.cells[0][0].char, "A")
    }
}
