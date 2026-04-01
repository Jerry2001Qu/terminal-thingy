import SwiftUI
import CoreText
import UIKit

// MARK: - Cell Metrics

struct CellMetrics {
    let fontSize: CGFloat
    let cellWidth: CGFloat
    let cellHeight: CGFloat

    static func calculate(cols: Int, availableWidth: CGFloat) -> CellMetrics {
        guard cols > 0, availableWidth > 0 else {
            return CellMetrics(fontSize: 12, cellWidth: 10, cellHeight: 16)
        }

        // Start with a nominal font size to measure the advance width of "W"
        let nominalSize: CGFloat = 16
        let nominalFont = CTFontCreateWithName("Menlo" as CFString, nominalSize, nil)
        let advance = measureAdvanceWidth(of: "W", font: nominalFont)

        // Scale so that advance * cols == availableWidth
        let scaledFontSize: CGFloat
        if advance > 0 {
            scaledFontSize = max(nominalSize * (availableWidth / (advance * CGFloat(cols))), 4)
        } else {
            scaledFontSize = max(availableWidth / CGFloat(cols) / 0.6, 4)
        }

        let finalFont = CTFontCreateWithName("Menlo" as CFString, scaledFontSize, nil)
        let finalAdvance = measureAdvanceWidth(of: "W", font: finalFont)
        let cellWidth = finalAdvance > 0 ? finalAdvance : (availableWidth / CGFloat(cols))

        // Cell height: ascent + descent + leading
        let ascent = CTFontGetAscent(finalFont)
        let descent = CTFontGetDescent(finalFont)
        let leading = CTFontGetLeading(finalFont)
        let cellHeight = CGFloat(ascent + descent + leading)

        return CellMetrics(
            fontSize: scaledFontSize,
            cellWidth: cellWidth,
            cellHeight: max(cellHeight, scaledFontSize * 1.2)
        )
    }

    private static func measureAdvanceWidth(of char: String, font: CTFont) -> CGFloat {
        var glyph = CGGlyph(0)
        var unichars = Array(char.utf16)
        CTFontGetGlyphsForCharacters(font, &unichars, &glyph, 1)
        var advance = CGSize.zero
        CTFontGetAdvancesForGlyphs(font, .horizontal, &glyph, &advance, 1)
        return advance.width
    }
}

// MARK: - Core Text UIView

final class TerminalCoreTextView: UIView {
    private var cells: [[TerminalCell]] = []
    private var cols: Int = 0
    private var rows: Int = 0
    private var cursorX: Int = -1
    private var cursorY: Int = -1
    private var metrics: CellMetrics = CellMetrics(fontSize: 12, cellWidth: 8, cellHeight: 16)

    // Color cache to avoid recreating CGColors on every draw
    private var colorCache: [String: CGColor] = [:]

    func update(cells: [[TerminalCell]], cols: Int, rows: Int,
                cursorX: Int, cursorY: Int, metrics: CellMetrics) {
        self.cells = cells
        self.cols = cols
        self.rows = rows
        self.cursorX = cursorX
        self.cursorY = cursorY
        self.metrics = metrics
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }

        let cellW = metrics.cellWidth
        let cellH = metrics.cellHeight
        let fontSize = metrics.fontSize

        // Fill background black
        context.setFillColor(UIColor.black.cgColor)
        context.fill(rect)

        // Core Text has origin at bottom-left; flip context so origin is top-left
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)

        let baseFont = CTFontCreateWithName("Menlo" as CFString, fontSize, nil)
        let boldFont = CTFontCreateCopyWithSymbolicTraits(baseFont, fontSize, nil, .boldTrait, .boldTrait)
            ?? CTFontCreateWithName("Menlo-Bold" as CFString, fontSize, nil)
        let italicFont = CTFontCreateCopyWithSymbolicTraits(baseFont, fontSize, nil, .italicTrait, .italicTrait)
            ?? CTFontCreateWithName("Menlo-Italic" as CFString, fontSize, nil)
        let boldItalicFont = CTFontCreateCopyWithSymbolicTraits(baseFont, fontSize, nil, [.boldTrait, .italicTrait], [.boldTrait, .italicTrait])
            ?? CTFontCreateWithName("Menlo-BoldItalic" as CFString, fontSize, nil)

        // Ascent to position text baseline within cell
        let ascent = CGFloat(CTFontGetAscent(baseFont))
        let descent = CGFloat(CTFontGetDescent(baseFont))

        for row in 0..<min(rows, cells.count) {
            let rowCells = cells[row]
            for col in 0..<min(cols, rowCells.count) {
                let cell = rowCells[col]

                // In flipped context, y=0 is bottom; row 0 is at top in screen space
                // Screen row 0 → bottom of flipped context = (rows - 1 - row) * cellH
                let screenRow = rows - 1 - row
                let x = CGFloat(col) * cellW
                let y = CGFloat(screenRow) * cellH

                let cellRect = CGRect(x: x, y: y, width: cellW, height: cellH)

                // Background
                if let bg = cell.bg {
                    let bgColor = cgColor(for: bg, defaultColor: nil)
                    if let bgColor = bgColor {
                        context.setFillColor(bgColor)
                        context.fill(cellRect)
                    }
                }

                // Cursor highlight
                if row == cursorY && col == cursorX {
                    context.setFillColor(UIColor.white.withAlphaComponent(0.3).cgColor)
                    context.fill(cellRect)
                }

                // Draw character
                guard cell.char != " " && !cell.char.isEmpty else { continue }

                let fgColor: CGColor
                if let fg = cell.fg {
                    fgColor = cgColor(for: fg, defaultColor: UIColor.white.cgColor) ?? UIColor.white.cgColor
                } else {
                    fgColor = UIColor.white.cgColor
                }

                let ctFont: CTFont
                if cell.bold && cell.italic {
                    ctFont = boldItalicFont
                } else if cell.bold {
                    ctFont = boldFont
                } else if cell.italic {
                    ctFont = italicFont
                } else {
                    ctFont = baseFont
                }

                var attrs: [NSAttributedString.Key: Any] = [
                    .font: ctFont,
                    .foregroundColor: fgColor
                ]

                if cell.underline {
                    attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
                    attrs[.underlineColor] = fgColor
                }

                let attrStr = NSAttributedString(string: cell.char, attributes: attrs)
                let line = CTLineCreateWithAttributedString(attrStr)

                // Baseline: bottom of cell rect + descent
                let baselineY = y + descent
                context.textPosition = CGPoint(x: x, y: baselineY)
                CTLineDraw(line, context)

                // Manual underline if needed (belt-and-suspenders for CT underline)
                if cell.underline {
                    context.setStrokeColor(fgColor)
                    context.setLineWidth(max(fontSize * 0.07, 1))
                    let underlineY = baselineY - descent * 0.3
                    context.move(to: CGPoint(x: x, y: underlineY))
                    context.addLine(to: CGPoint(x: x + cellW, y: underlineY))
                    context.strokePath()
                }
            }
        }
    }

    private func cgColor(for hex: String, defaultColor: CGColor?) -> CGColor? {
        if let cached = colorCache[hex] { return cached }

        var h = hex
        if h.hasPrefix("#") { h = String(h.dropFirst()) }
        if h.count == 3 {
            h = h.map { "\($0)\($0)" }.joined()
        }
        guard h.count == 6, let val = UInt64(h, radix: 16) else {
            return defaultColor
        }

        let r = CGFloat((val >> 16) & 0xff) / 255.0
        let g = CGFloat((val >> 8) & 0xff) / 255.0
        let b = CGFloat(val & 0xff) / 255.0
        let color = CGColor(red: r, green: g, blue: b, alpha: 1.0)
        colorCache[hex] = color
        return color
    }
}

// MARK: - UIViewRepresentable

private struct TerminalCoreTextRepresentable: UIViewRepresentable {
    let cells: [[TerminalCell]]
    let cols: Int
    let rows: Int
    let cursorX: Int
    let cursorY: Int
    let metrics: CellMetrics

    func makeUIView(context: Context) -> TerminalCoreTextView {
        let view = TerminalCoreTextView()
        view.backgroundColor = .black
        view.isOpaque = true
        return view
    }

    func updateUIView(_ view: TerminalCoreTextView, context: Context) {
        view.update(cells: cells, cols: cols, rows: rows,
                    cursorX: cursorX, cursorY: cursorY, metrics: metrics)
        view.setNeedsDisplay()
    }
}

// MARK: - Public SwiftUI View (same interface as before)

struct TerminalCanvas: View {
    let cells: [[TerminalCell]]
    let cols: Int
    let rows: Int
    let cursorX: Int
    let cursorY: Int
    let availableWidth: CGFloat

    private var cellMetrics: CellMetrics {
        CellMetrics.calculate(cols: cols, availableWidth: availableWidth)
    }

    var totalHeight: CGFloat {
        cellMetrics.cellHeight * CGFloat(rows)
    }

    var body: some View {
        TerminalCoreTextRepresentable(
            cells: cells,
            cols: cols,
            rows: rows,
            cursorX: cursorX,
            cursorY: cursorY,
            metrics: cellMetrics
        )
        .frame(height: totalHeight)
    }
}

// MARK: - Color utility (kept for use elsewhere)

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
