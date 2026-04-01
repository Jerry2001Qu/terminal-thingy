import pkg from '@xterm/headless';
const { Terminal } = pkg;

// ANSI 16-color palette
const PALETTE_16 = [
  '#000000', '#cd0000', '#00cd00', '#cdcd00', '#0000ee', '#cd00cd', '#00cdcd', '#e5e5e5',
  '#7f7f7f', '#ff0000', '#00ff00', '#ffff00', '#5c5cff', '#ff00ff', '#00ffff', '#ffffff',
];

export class VirtualTerminal {
  constructor(cols, rows, scrollbackLimit) {
    this.terminal = new Terminal({
      cols,
      rows,
      scrollback: scrollbackLimit,
      allowProposedApi: true,
    });
    this.previousState = null;
    this.lastBaseY = 0;
    this.scrollbackLines = [];
    this.scrollbackLimit = scrollbackLimit;
  }

  write(data) {
    this.terminal.write(data);
  }

  resize(cols, rows) {
    this.terminal.resize(cols, rows);
    this.previousState = null; // Force full state on next getDiff
  }

  getState() {
    const buffer = this.terminal.buffer.active;
    const cells = [];
    for (let row = 0; row < this.terminal.rows; row++) {
      const line = buffer.getLine(buffer.baseY + row);
      cells.push(this._extractLine(line, this.terminal.cols));
    }
    return {
      type: 'state',
      cols: this.terminal.cols,
      rows: this.terminal.rows,
      cells,
      cursorX: buffer.cursorX,
      cursorY: buffer.cursorY,
    };
  }

  _extractLine(line, cols) {
    const cells = [];
    for (let col = 0; col < cols; col++) {
      if (!line) {
        cells.push({ char: ' ', fg: null, bg: null, bold: false, italic: false, underline: false });
        continue;
      }
      const cell = line.getCell(col);
      if (!cell) {
        cells.push({ char: ' ', fg: null, bg: null, bold: false, italic: false, underline: false });
        continue;
      }
      cells.push({
        char: cell.getChars() || ' ',
        fg: this._resolveColor(cell.getFgColor(), cell.getFgColorMode()),
        bg: this._resolveColor(cell.getBgColor(), cell.getBgColorMode()),
        bold: cell.isBold() === 1,
        italic: cell.isItalic() === 1,
        underline: cell.isUnderline() === 1,
      });
    }
    return cells;
  }

  _resolveColor(color, mode) {
    if (mode === 0) return null; // Default color
    if (mode === 1) return PALETTE_16[color] || null; // 16-color palette
    if (mode === 2) return this._palette256(color); // 256-color palette
    if (mode === 3) {
      // RGB: color is packed as (r << 16) | (g << 8) | b
      const r = (color >> 16) & 0xff;
      const g = (color >> 8) & 0xff;
      const b = color & 0xff;
      return `#${r.toString(16).padStart(2, '0')}${g.toString(16).padStart(2, '0')}${b.toString(16).padStart(2, '0')}`;
    }
    return null;
  }

  _palette256(index) {
    if (index < 16) return PALETTE_16[index];
    if (index < 232) {
      // 6x6x6 color cube (indices 16-231)
      const i = index - 16;
      const r = Math.floor(i / 36) * 51;
      const g = Math.floor((i % 36) / 6) * 51;
      const b = (i % 6) * 51;
      return `#${r.toString(16).padStart(2, '0')}${g.toString(16).padStart(2, '0')}${b.toString(16).padStart(2, '0')}`;
    }
    // Grayscale ramp (indices 232-255)
    const gray = (index - 232) * 10 + 8;
    return `#${gray.toString(16).padStart(2, '0')}${gray.toString(16).padStart(2, '0')}${gray.toString(16).padStart(2, '0')}`;
  }

  getDiff() {
    const current = this.getState();
    if (!this.previousState) {
      this.previousState = current;
      return null;
    }

    const changes = [];
    for (let row = 0; row < current.rows; row++) {
      if (this._rowChanged(this.previousState.cells[row], current.cells[row])) {
        changes.push({ row, col: 0, cells: current.cells[row] });
      }
    }

    const cursorMoved =
      current.cursorX !== this.previousState.cursorX ||
      current.cursorY !== this.previousState.cursorY;

    this.previousState = current;

    if (changes.length === 0 && !cursorMoved) return null;

    return {
      type: 'diff',
      changes,
      cursorX: current.cursorX,
      cursorY: current.cursorY,
    };
  }

  _rowChanged(prevRow, currRow) {
    if (!prevRow || !currRow) return true;
    if (prevRow.length !== currRow.length) return true;
    for (let col = 0; col < currRow.length; col++) {
      const p = prevRow[col];
      const c = currRow[col];
      if (
        p.char !== c.char ||
        p.fg !== c.fg ||
        p.bg !== c.bg ||
        p.bold !== c.bold ||
        p.italic !== c.italic ||
        p.underline !== c.underline
      ) {
        return true;
      }
    }
    return false;
  }

  collectScrollback() {
    const buffer = this.terminal.buffer.active;
    const currentBaseY = buffer.baseY;
    const newLines = [];

    if (currentBaseY > this.lastBaseY) {
      for (let y = this.lastBaseY; y < currentBaseY; y++) {
        const line = buffer.getLine(y);
        newLines.push(this._extractLine(line, this.terminal.cols));
      }
      this.lastBaseY = currentBaseY;

      this.scrollbackLines.push(...newLines);
      if (this.scrollbackLines.length > this.scrollbackLimit) {
        this.scrollbackLines = this.scrollbackLines.slice(-this.scrollbackLimit);
      }
    }

    return newLines;
  }

  getScrollbackBuffer() {
    return this.scrollbackLines;
  }

  destroy() {
    this.terminal.dispose();
  }
}
