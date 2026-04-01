import SwiftUI

struct TerminalCanvas: View {
    let cells: [[TerminalCell]]
    let cols: Int
    let rows: Int
    let cursorX: Int
    let cursorY: Int
    let availableWidth: CGFloat

    private var cellWidth: CGFloat {
        guard cols > 0 else { return 10 }
        return availableWidth / CGFloat(cols)
    }

    private var fontSize: CGFloat {
        // Monospaced system font: char width ≈ 0.6 * fontSize
        // Solve: cellWidth = 0.6 * fontSize → fontSize = cellWidth / 0.6
        max(cellWidth / 0.6, 4)
    }

    private var cellHeight: CGFloat {
        fontSize * 1.3
    }

    private var totalHeight: CGFloat {
        CGFloat(rows) * cellHeight
    }

    var body: some View {
        Canvas { context, size in
            let font = Font.system(size: fontSize, design: .monospaced)

            for row in 0..<min(rows, cells.count) {
                let rowCells = cells[row]
                for col in 0..<min(cols, rowCells.count) {
                    let cell = rowCells[col]
                    let x = CGFloat(col) * cellWidth
                    let y = CGFloat(row) * cellHeight

                    let rect = CGRect(x: x, y: y, width: cellWidth, height: cellHeight)

                    // Background
                    if let bg = cell.bg {
                        context.fill(Path(rect), with: .color(colorFromHex(bg)))
                    }

                    // Cursor
                    if row == cursorY && col == cursorX {
                        context.fill(Path(rect), with: .color(.white.opacity(0.3)))
                    }

                    // Character
                    if cell.char != " " {
                        let fgColor = cell.fg.map { colorFromHex($0) } ?? .white
                        // Use monospaced for ASCII, system font for symbols (better glyph coverage)
                        let isASCII = cell.char.unicodeScalars.first.map { $0.value < 128 } ?? false
                        let charFont = isASCII
                            ? Font.system(size: fontSize, design: .monospaced)
                            : Font.system(size: fontSize * 0.85)
                        var text = Text(cell.char)
                            .font(charFont)
                            .foregroundColor(fgColor)
                        if cell.bold {
                            text = text.bold()
                        }
                        if cell.italic {
                            text = text.italic()
                        }
                        if cell.underline {
                            text = text.underline()
                        }
                        context.draw(text, at: CGPoint(x: x + cellWidth / 2, y: y + cellHeight / 2))
                    }
                }
            }
        }
        .frame(height: totalHeight)
    }
}

func colorFromHex(_ hex: String) -> Color {
    var h = hex
    if h.hasPrefix("#") { h = String(h.dropFirst()) }

    // Handle 3-char shorthand (#fff → #ffffff)
    if h.count == 3 {
        h = h.map { "\($0)\($0)" }.joined()
    }

    guard h.count == 6,
          let val = UInt64(h, radix: 16) else {
        return .white
    }

    let r = Double((val >> 16) & 0xff) / 255.0
    let g = Double((val >> 8) & 0xff) / 255.0
    let b = Double(val & 0xff) / 255.0
    return Color(red: r, green: g, blue: b)
}
