import Foundation

class TerminalGrid: ObservableObject {
    @Published var cols: Int = 0
    @Published var rows: Int = 0
    @Published var cells: [[TerminalCell]] = []
    @Published var cursorX: Int = 0
    @Published var cursorY: Int = 0
    @Published var scrollbackLines: [[TerminalCell]] = []

    func applyState(_ state: StateMessage) {
        cols = state.cols
        rows = state.rows
        cells = state.cells
        cursorX = state.cursorX
        cursorY = state.cursorY
    }

    func applyDiff(_ diff: DiffMessage) {
        for change in diff.changes {
            guard change.row < cells.count else { continue }
            if change.col == 0 && change.cells.count >= cols {
                // Full row replacement
                cells[change.row] = change.cells
            } else {
                // Partial row update starting at col offset
                var row = cells[change.row]
                for (i, cell) in change.cells.enumerated() {
                    let targetCol = change.col + i
                    if targetCol < row.count {
                        row[targetCol] = cell
                    }
                }
                cells[change.row] = row
            }
        }
        cursorX = diff.cursorX
        cursorY = diff.cursorY
    }

    func appendScrollback(_ lines: [[TerminalCell]]) {
        scrollbackLines.append(contentsOf: lines)
    }

    func applyResize(_ resize: ResizeMessage) {
        cols = resize.cols
        rows = resize.rows
    }
}
