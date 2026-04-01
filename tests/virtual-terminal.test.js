import { describe, it, expect } from 'vitest';
import { VirtualTerminal } from '../src/virtual-terminal.js';

describe('VirtualTerminal', () => {
  describe('getState', () => {
    it('returns state with correct dimensions', () => {
      const vt = new VirtualTerminal(10, 5, 100);
      const state = vt.getState();
      expect(state.type).toBe('state');
      expect(state.cols).toBe(10);
      expect(state.rows).toBe(5);
      expect(state.cells.length).toBe(5);
      expect(state.cells[0].length).toBe(10);
      expect(state.cursorX).toBe(0);
      expect(state.cursorY).toBe(0);
    });

    it('empty cells have space characters', () => {
      const vt = new VirtualTerminal(10, 5, 100);
      const state = vt.getState();
      expect(state.cells[0][0].char).toBe(' ');
    });
  });

  describe('write', () => {
    it('updates cell content after write', async () => {
      const vt = new VirtualTerminal(10, 5, 100);
      // xterm-headless write may be async — use a small delay
      await new Promise((resolve) => vt.terminal.write('hello', resolve));
      const state = vt.getState();
      expect(state.cells[0][0].char).toBe('h');
      expect(state.cells[0][1].char).toBe('e');
      expect(state.cells[0][2].char).toBe('l');
      expect(state.cells[0][3].char).toBe('l');
      expect(state.cells[0][4].char).toBe('o');
      expect(state.cursorX).toBe(5);
      expect(state.cursorY).toBe(0);
    });
  });

  describe('getDiff', () => {
    it('returns null on first call (no previous state)', async () => {
      const vt = new VirtualTerminal(10, 5, 100);
      expect(vt.getDiff()).toBeNull();
    });

    it('returns null when nothing changed', async () => {
      const vt = new VirtualTerminal(10, 5, 100);
      vt.getDiff(); // Initialize previous state
      const diff = vt.getDiff();
      expect(diff).toBeNull();
    });

    it('detects changed rows after write', async () => {
      const vt = new VirtualTerminal(10, 5, 100);
      vt.getDiff(); // Initialize previous state
      await new Promise((resolve) => vt.terminal.write('hi', resolve));
      const diff = vt.getDiff();
      expect(diff).not.toBeNull();
      expect(diff.type).toBe('diff');
      expect(diff.changes.length).toBeGreaterThan(0);
      expect(diff.changes[0].row).toBe(0);
      expect(diff.changes[0].cells[0].char).toBe('h');
    });

    it('detects cursor movement', async () => {
      const vt = new VirtualTerminal(10, 5, 100);
      vt.getDiff(); // Initialize
      // Move cursor with ANSI escape: ESC[3;5H moves cursor to row 3, col 5 (1-indexed)
      await new Promise((resolve) => vt.terminal.write('\x1b[3;5H', resolve));
      const diff = vt.getDiff();
      expect(diff).not.toBeNull();
      expect(diff.cursorX).toBe(4); // 0-indexed
      expect(diff.cursorY).toBe(2); // 0-indexed
    });
  });

  describe('collectScrollback', () => {
    it('returns empty when no scrollback', () => {
      const vt = new VirtualTerminal(10, 3, 100);
      expect(vt.collectScrollback()).toEqual([]);
    });

    it('captures lines that scroll off the top', async () => {
      const vt = new VirtualTerminal(10, 3, 100);
      // Write 5 lines into a 3-row terminal — 2 should scroll off
      await new Promise((resolve) =>
        vt.terminal.write('line1\r\nline2\r\nline3\r\nline4\r\nline5', resolve)
      );
      const scrollback = vt.collectScrollback();
      expect(scrollback.length).toBe(2);
      expect(scrollback[0][0].char).toBe('l'); // "line1"
      expect(scrollback[0][1].char).toBe('i');
    });

    it('does not return same lines twice', async () => {
      const vt = new VirtualTerminal(10, 3, 100);
      await new Promise((resolve) =>
        vt.terminal.write('line1\r\nline2\r\nline3\r\nline4\r\nline5', resolve)
      );
      vt.collectScrollback();
      const second = vt.collectScrollback();
      expect(second).toEqual([]);
    });

    it('getScrollbackBuffer returns all collected lines', async () => {
      const vt = new VirtualTerminal(10, 3, 100);
      await new Promise((resolve) =>
        vt.terminal.write('line1\r\nline2\r\nline3\r\nline4\r\nline5', resolve)
      );
      vt.collectScrollback();
      expect(vt.getScrollbackBuffer().length).toBe(2);
    });
  });

  describe('resize', () => {
    it('updates dimensions', () => {
      const vt = new VirtualTerminal(10, 5, 100);
      vt.resize(20, 10);
      const state = vt.getState();
      expect(state.cols).toBe(20);
      expect(state.rows).toBe(10);
      expect(state.cells.length).toBe(10);
      expect(state.cells[0].length).toBe(20);
    });

    it('forces full state on next getDiff', async () => {
      const vt = new VirtualTerminal(10, 5, 100);
      vt.getDiff(); // Initialize
      vt.resize(20, 10);
      // getDiff should return null (previousState was cleared)
      expect(vt.getDiff()).toBeNull();
      // Next getDiff should work normally
      await new Promise((resolve) => vt.terminal.write('x', resolve));
      const diff = vt.getDiff();
      expect(diff).not.toBeNull();
    });
  });
});
