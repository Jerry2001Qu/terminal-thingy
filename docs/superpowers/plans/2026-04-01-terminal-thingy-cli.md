# terminal-thingy CLI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Node.js CLI that wraps the user's shell in a PTY, maintains a headless virtual terminal, and streams screen state to connected clients over an encrypted WebSocket.

**Architecture:** The CLI spawns a PTY with the user's shell, feeds output into `@xterm/headless` for state tracking, and runs a WebSocket server that broadcasts diffs at ~30fps. Bonjour advertises the service for auto-discovery; a QR code provides one-scan connection. AES-256-GCM encryption is on by default using a 6-digit code + HKDF-derived key.

**Tech Stack:** Node.js (ESM), node-pty, @xterm/headless, ws, bonjour-service, qrcode-terminal, commander, vitest

**Spec:** `docs/superpowers/specs/2026-04-01-terminal-thingy-design.md`

**Note:** This plan covers the CLI only. The iOS app is a separate plan.

**Simplification from spec:** The spec describes a separate "token" and "PIN". This plan uses a single 6-digit numeric code as both the auth credential and human-friendly PIN. The encryption key is derived from code + random salt via HKDF. The salt is public (included in QR URL and Bonjour TXT record). This is secure for a local-network, session-scoped, read-only tool.

---

## File Structure

```
terminal-thingy/
├── package.json
├── vitest.config.js
├── bin/
│   └── terminal-thingy.js           # CLI entry point + arg parsing
├── src/
│   ├── app.js                        # Main orchestrator — wires all modules
│   ├── auth.js                       # Code generation, HKDF key derivation, AES-256-GCM encrypt/decrypt
│   ├── pty-manager.js                # PTY spawn, stdin/stdout proxy, resize, cleanup
│   ├── virtual-terminal.js           # xterm-headless wrapper, state extraction, diff engine, scrollback
│   ├── server.js                     # WebSocket server, auth handshake, encrypted broadcast
│   └── discovery.js                  # Bonjour advertisement + QR code display
└── tests/
    ├── auth.test.js
    ├── virtual-terminal.test.js
    ├── server.test.js
    └── integration.test.js
```

---

### Task 1: Project Setup

**Files:**
- Create: `package.json`
- Create: `vitest.config.js`
- Create: `bin/terminal-thingy.js` (stub)
- Create: `src/app.js` (stub)

- [ ] **Step 1: Initialize package.json**

```json
{
  "name": "terminal-thingy",
  "version": "0.1.0",
  "description": "Stream your terminal to your phone",
  "type": "module",
  "bin": {
    "terminal-thingy": "./bin/terminal-thingy.js"
  },
  "scripts": {
    "test": "vitest run",
    "test:watch": "vitest"
  },
  "engines": {
    "node": ">=18.0.0"
  },
  "license": "MIT"
}
```

- [ ] **Step 2: Install dependencies**

Run:
```bash
npm install node-pty @xterm/headless ws bonjour-service qrcode-terminal commander
npm install -D vitest
```

- [ ] **Step 3: Create vitest config**

Create `vitest.config.js`:

```javascript
import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    testTimeout: 10000,
  },
});
```

- [ ] **Step 4: Create stub entry point**

Create `bin/terminal-thingy.js`:

```javascript
#!/usr/bin/env node
import { startApp } from '../src/app.js';

startApp(process.argv.slice(2));
```

Create `src/app.js`:

```javascript
export function startApp(argv) {
  console.log('terminal-thingy starting...', argv);
}
```

- [ ] **Step 5: Verify setup**

Run: `node bin/terminal-thingy.js`
Expected: Prints `terminal-thingy starting... []`

Run: `npx vitest run`
Expected: No tests found (or passes with 0 tests)

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "project setup with dependencies and stub entry point"
```

---

### Task 2: Auth Module

**Files:**
- Create: `src/auth.js`
- Create: `tests/auth.test.js`

- [ ] **Step 1: Write test for code generation**

Create `tests/auth.test.js`:

```javascript
import { describe, it, expect } from 'vitest';
import { generateCode } from '../src/auth.js';

describe('generateCode', () => {
  it('returns a 6-digit numeric string', () => {
    const code = generateCode();
    expect(code).toMatch(/^\d{6}$/);
  });

  it('generates different codes on each call', () => {
    const codes = new Set(Array.from({ length: 10 }, () => generateCode()));
    expect(codes.size).toBeGreaterThan(1);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npx vitest run tests/auth.test.js`
Expected: FAIL — `generateCode` not found

- [ ] **Step 3: Implement code generation**

Create `src/auth.js`:

```javascript
import crypto from 'node:crypto';

export function generateCode() {
  const num = crypto.randomInt(0, 1000000);
  return num.toString().padStart(6, '0');
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npx vitest run tests/auth.test.js`
Expected: PASS

- [ ] **Step 5: Write test for salt generation and key derivation**

Add to `tests/auth.test.js`:

```javascript
import { generateCode, generateSalt, deriveKey } from '../src/auth.js';

describe('generateSalt', () => {
  it('returns a 16-byte hex string', () => {
    const salt = generateSalt();
    expect(salt).toMatch(/^[0-9a-f]{32}$/);
  });
});

describe('deriveKey', () => {
  it('returns a 32-byte buffer', () => {
    const key = deriveKey('123456', 'ab'.repeat(16));
    expect(key).toBeInstanceOf(Buffer);
    expect(key.length).toBe(32);
  });

  it('same inputs produce same key', () => {
    const salt = generateSalt();
    const k1 = deriveKey('123456', salt);
    const k2 = deriveKey('123456', salt);
    expect(k1.equals(k2)).toBe(true);
  });

  it('different codes produce different keys', () => {
    const salt = generateSalt();
    const k1 = deriveKey('123456', salt);
    const k2 = deriveKey('654321', salt);
    expect(k1.equals(k2)).toBe(false);
  });
});
```

- [ ] **Step 6: Run test to verify it fails**

Run: `npx vitest run tests/auth.test.js`
Expected: FAIL — `generateSalt`, `deriveKey` not found

- [ ] **Step 7: Implement salt generation and key derivation**

Add to `src/auth.js`:

```javascript
export function generateSalt() {
  return crypto.randomBytes(16).toString('hex');
}

export function deriveKey(code, salt) {
  return crypto.hkdfSync('sha256', code, Buffer.from(salt, 'hex'), 'terminal-thingy', 32);
}
```

Note: `crypto.hkdfSync` returns an `ArrayBuffer`. Wrap it:

```javascript
export function deriveKey(code, salt) {
  const derived = crypto.hkdfSync('sha256', code, Buffer.from(salt, 'hex'), 'terminal-thingy', 32);
  return Buffer.from(derived);
}
```

- [ ] **Step 8: Run test to verify it passes**

Run: `npx vitest run tests/auth.test.js`
Expected: PASS

- [ ] **Step 9: Write test for encrypt/decrypt round-trip**

Add to `tests/auth.test.js`:

```javascript
import { generateCode, generateSalt, deriveKey, encrypt, decrypt } from '../src/auth.js';

describe('encrypt/decrypt', () => {
  it('round-trips a string', () => {
    const key = deriveKey('123456', generateSalt());
    const plaintext = JSON.stringify({ type: 'state', cols: 80, rows: 24 });
    const ciphertext = encrypt(plaintext, key);
    expect(ciphertext).not.toBe(plaintext);
    const decrypted = decrypt(ciphertext, key);
    expect(decrypted).toBe(plaintext);
  });

  it('different keys cannot decrypt', () => {
    const salt = generateSalt();
    const key1 = deriveKey('123456', salt);
    const key2 = deriveKey('654321', salt);
    const ciphertext = encrypt('hello', key1);
    expect(() => decrypt(ciphertext, key2)).toThrow();
  });

  it('same plaintext produces different ciphertext (random IV)', () => {
    const key = deriveKey('123456', generateSalt());
    const c1 = encrypt('hello', key);
    const c2 = encrypt('hello', key);
    expect(c1).not.toBe(c2);
  });
});
```

- [ ] **Step 10: Run test to verify it fails**

Run: `npx vitest run tests/auth.test.js`
Expected: FAIL — `encrypt`, `decrypt` not found

- [ ] **Step 11: Implement encrypt and decrypt**

Add to `src/auth.js`:

```javascript
export function encrypt(plaintext, key) {
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', key, iv);
  const encrypted = Buffer.concat([
    cipher.update(plaintext, 'utf8'),
    cipher.final(),
  ]);
  const authTag = cipher.getAuthTag();
  // Format: base64(iv + authTag + ciphertext)
  return Buffer.concat([iv, authTag, encrypted]).toString('base64');
}

export function decrypt(ciphertext, key) {
  const buf = Buffer.from(ciphertext, 'base64');
  const iv = buf.subarray(0, 12);
  const authTag = buf.subarray(12, 28);
  const encrypted = buf.subarray(28);
  const decipher = crypto.createDecipheriv('aes-256-gcm', key, iv);
  decipher.setAuthTag(authTag);
  return decipher.update(encrypted, null, 'utf8') + decipher.final('utf8');
}
```

- [ ] **Step 12: Run test to verify it passes**

Run: `npx vitest run tests/auth.test.js`
Expected: PASS

- [ ] **Step 13: Write test for formatCode helper**

Add to `tests/auth.test.js`:

```javascript
import { generateCode, generateSalt, deriveKey, encrypt, decrypt, formatCode } from '../src/auth.js';

describe('formatCode', () => {
  it('formats as XXX XXX', () => {
    expect(formatCode('847291')).toBe('847 291');
  });
});
```

- [ ] **Step 14: Implement formatCode**

Add to `src/auth.js`:

```javascript
export function formatCode(code) {
  return `${code.slice(0, 3)} ${code.slice(3)}`;
}
```

- [ ] **Step 15: Run all auth tests**

Run: `npx vitest run tests/auth.test.js`
Expected: All PASS

- [ ] **Step 16: Commit**

```bash
git add src/auth.js tests/auth.test.js
git commit -m "add auth module: code generation, HKDF key derivation, AES-256-GCM encrypt/decrypt"
```

---

### Task 3: Virtual Terminal + Diff Engine

**Files:**
- Create: `src/virtual-terminal.js`
- Create: `tests/virtual-terminal.test.js`

- [ ] **Step 1: Write test for state extraction from empty terminal**

Create `tests/virtual-terminal.test.js`:

```javascript
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
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npx vitest run tests/virtual-terminal.test.js`
Expected: FAIL — `VirtualTerminal` not found

- [ ] **Step 3: Implement VirtualTerminal with getState**

Create `src/virtual-terminal.js`:

```javascript
import { Terminal } from '@xterm/headless';

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
    if (mode === 2) return null; // 256-color — return index, let client resolve
    if (mode === 3) {
      // RGB: color is packed as (r << 16) | (g << 8) | b
      const r = (color >> 16) & 0xff;
      const g = (color >> 8) & 0xff;
      const b = color & 0xff;
      return `#${r.toString(16).padStart(2, '0')}${g.toString(16).padStart(2, '0')}${b.toString(16).padStart(2, '0')}`;
    }
    return null;
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npx vitest run tests/virtual-terminal.test.js`
Expected: PASS

- [ ] **Step 5: Write test for write and state update**

Add to `tests/virtual-terminal.test.js`:

```javascript
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
```

- [ ] **Step 6: Run test to verify it passes**

Run: `npx vitest run tests/virtual-terminal.test.js`
Expected: PASS (write is synchronous in headless mode, but the callback ensures processing is complete)

- [ ] **Step 7: Write test for diff engine**

Add to `tests/virtual-terminal.test.js`:

```javascript
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
```

- [ ] **Step 8: Run test to verify it passes**

Run: `npx vitest run tests/virtual-terminal.test.js`
Expected: PASS

- [ ] **Step 9: Write test for scrollback collection**

Add to `tests/virtual-terminal.test.js`:

```javascript
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
```

- [ ] **Step 10: Run test to verify it passes**

Run: `npx vitest run tests/virtual-terminal.test.js`
Expected: PASS

- [ ] **Step 11: Write test for resize**

Add to `tests/virtual-terminal.test.js`:

```javascript
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
```

- [ ] **Step 12: Run all virtual terminal tests**

Run: `npx vitest run tests/virtual-terminal.test.js`
Expected: All PASS

- [ ] **Step 13: Commit**

```bash
git add src/virtual-terminal.js tests/virtual-terminal.test.js
git commit -m "add virtual terminal with diff engine and scrollback tracking"
```

---

### Task 4: WebSocket Server

**Files:**
- Create: `src/server.js`
- Create: `tests/server.test.js`

- [ ] **Step 1: Write test for server start and connection**

Create `tests/server.test.js`:

```javascript
import { describe, it, expect, afterEach } from 'vitest';
import WebSocket from 'ws';
import { StreamServer } from '../src/server.js';

describe('StreamServer', () => {
  let server;

  afterEach(async () => {
    if (server) await server.close();
  });

  it('starts on a given port and accepts connections', async () => {
    server = new StreamServer({ port: 0, auth: false });
    const address = await server.start();
    expect(address.port).toBeGreaterThan(0);

    const ws = new WebSocket(`ws://127.0.0.1:${address.port}`);
    await new Promise((resolve) => ws.on('open', resolve));
    expect(ws.readyState).toBe(WebSocket.OPEN);
    ws.close();
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npx vitest run tests/server.test.js`
Expected: FAIL — `StreamServer` not found

- [ ] **Step 3: Implement basic StreamServer**

Create `src/server.js`:

```javascript
import { WebSocketServer } from 'ws';
import { URL } from 'node:url';
import { encrypt, deriveKey } from './auth.js';

export class StreamServer {
  constructor({ port = 0, host = '0.0.0.0', auth = true, code = null, salt = null }) {
    this.port = port;
    this.host = host;
    this.auth = auth;
    this.code = code;
    this.salt = salt;
    this.key = auth && code && salt ? deriveKey(code, salt) : null;
    this.wss = null;
    this.clients = new Set();
  }

  start() {
    return new Promise((resolve, reject) => {
      this.wss = new WebSocketServer({ port: this.port, host: this.host });

      this.wss.on('listening', () => {
        resolve(this.wss.address());
      });

      this.wss.on('error', reject);

      this.wss.on('connection', (ws, req) => {
        if (this.auth) {
          const url = new URL(req.url, `http://${req.headers.host}`);
          const clientCode = url.searchParams.get('code');
          if (clientCode !== this.code) {
            ws.close(4001, 'Invalid code');
            return;
          }
        }

        this.clients.add(ws);
        ws.on('close', () => this.clients.delete(ws));
        ws.on('error', () => this.clients.delete(ws));

        if (this._onConnect) this._onConnect(ws);
      });
    });
  }

  onConnect(handler) {
    this._onConnect = handler;
  }

  broadcast(message) {
    const json = JSON.stringify(message);
    const payload = this.key ? encrypt(json, this.key) : json;
    for (const client of this.clients) {
      if (client.readyState === 1) { // WebSocket.OPEN
        client.send(payload);
      }
    }
  }

  send(ws, message) {
    const json = JSON.stringify(message);
    const payload = this.key ? encrypt(json, this.key) : json;
    if (ws.readyState === 1) {
      ws.send(payload);
    }
  }

  clientCount() {
    return this.clients.size;
  }

  close() {
    return new Promise((resolve) => {
      if (!this.wss) return resolve();
      for (const client of this.clients) {
        client.close();
      }
      this.wss.close(resolve);
    });
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npx vitest run tests/server.test.js`
Expected: PASS

- [ ] **Step 5: Write test for auth rejection**

Add to `tests/server.test.js`:

```javascript
import { generateCode, generateSalt, deriveKey, decrypt } from '../src/auth.js';

it('rejects connection without valid code', async () => {
  const code = '123456';
  const salt = 'ab'.repeat(16);
  server = new StreamServer({ port: 0, auth: true, code, salt });
  const address = await server.start();

  const ws = new WebSocket(`ws://127.0.0.1:${address.port}?code=wrong`);
  const closeCode = await new Promise((resolve) => ws.on('close', (code) => resolve(code)));
  expect(closeCode).toBe(4001);
});

it('accepts connection with valid code', async () => {
  const code = '123456';
  const salt = 'ab'.repeat(16);
  server = new StreamServer({ port: 0, auth: true, code, salt });
  const address = await server.start();

  const ws = new WebSocket(`ws://127.0.0.1:${address.port}?code=123456`);
  await new Promise((resolve) => ws.on('open', resolve));
  expect(ws.readyState).toBe(WebSocket.OPEN);
  ws.close();
});
```

- [ ] **Step 6: Run test to verify it passes**

Run: `npx vitest run tests/server.test.js`
Expected: PASS

- [ ] **Step 7: Write test for encrypted broadcast**

Add to `tests/server.test.js`:

```javascript
it('broadcasts encrypted messages when auth is on', async () => {
  const code = '123456';
  const salt = 'ab'.repeat(16);
  server = new StreamServer({ port: 0, auth: true, code, salt });
  const address = await server.start();

  const ws = new WebSocket(`ws://127.0.0.1:${address.port}?code=${code}`);
  await new Promise((resolve) => ws.on('open', resolve));

  const received = new Promise((resolve) => ws.on('message', (data) => resolve(data.toString())));
  server.broadcast({ type: 'state', cols: 80, rows: 24 });

  const ciphertext = await received;
  // Should be base64 (encrypted), not plain JSON
  expect(() => JSON.parse(ciphertext)).toThrow();

  // Should decrypt to original message
  const key = deriveKey(code, salt);
  const decrypted = JSON.parse(decrypt(ciphertext, key));
  expect(decrypted.type).toBe('state');
  expect(decrypted.cols).toBe(80);

  ws.close();
});

it('broadcasts plain JSON when auth is off', async () => {
  server = new StreamServer({ port: 0, auth: false });
  const address = await server.start();

  const ws = new WebSocket(`ws://127.0.0.1:${address.port}`);
  await new Promise((resolve) => ws.on('open', resolve));

  const received = new Promise((resolve) => ws.on('message', (data) => resolve(data.toString())));
  server.broadcast({ type: 'state', cols: 80, rows: 24 });

  const json = await received;
  const parsed = JSON.parse(json);
  expect(parsed.type).toBe('state');

  ws.close();
});
```

- [ ] **Step 8: Run test to verify it passes**

Run: `npx vitest run tests/server.test.js`
Expected: PASS

- [ ] **Step 9: Write test for onConnect callback and send**

Add to `tests/server.test.js`:

```javascript
it('calls onConnect and send works for individual client', async () => {
  server = new StreamServer({ port: 0, auth: false });
  const address = await server.start();

  let connectedWs;
  server.onConnect((ws) => {
    connectedWs = ws;
    server.send(ws, { type: 'state', cols: 120, rows: 24 });
  });

  const ws = new WebSocket(`ws://127.0.0.1:${address.port}`);
  const received = new Promise((resolve) => ws.on('message', (data) => resolve(data.toString())));
  await new Promise((resolve) => ws.on('open', resolve));

  const json = await received;
  const parsed = JSON.parse(json);
  expect(parsed.type).toBe('state');
  expect(parsed.cols).toBe(120);

  ws.close();
});
```

- [ ] **Step 10: Run all server tests**

Run: `npx vitest run tests/server.test.js`
Expected: All PASS

- [ ] **Step 11: Commit**

```bash
git add src/server.js tests/server.test.js
git commit -m "add WebSocket server with auth, encryption, and broadcast"
```

---

### Task 5: PTY Manager

**Files:**
- Create: `src/pty-manager.js`
- Create: `tests/pty-manager.test.js`

- [ ] **Step 1: Write test for PTY spawn and output**

Create `tests/pty-manager.test.js`:

```javascript
import { describe, it, expect, afterEach } from 'vitest';
import { PtyManager } from '../src/pty-manager.js';

describe('PtyManager', () => {
  let pty;

  afterEach(() => {
    if (pty) pty.destroy();
  });

  it('spawns a shell and receives output', async () => {
    pty = new PtyManager({ shell: '/bin/echo', args: ['hello'] });
    pty.spawn(80, 24);

    const output = await new Promise((resolve) => {
      let data = '';
      pty.onData((chunk) => {
        data += chunk;
        if (data.includes('hello')) resolve(data);
      });
      // Timeout safety
      setTimeout(() => resolve(data), 3000);
    });

    expect(output).toContain('hello');
  });

  it('reports correct dimensions', () => {
    pty = new PtyManager({ shell: '/bin/sh' });
    pty.spawn(120, 40);
    expect(pty.cols).toBe(120);
    expect(pty.rows).toBe(40);
  });

  it('resizes the PTY', () => {
    pty = new PtyManager({ shell: '/bin/sh' });
    pty.spawn(80, 24);
    pty.resize(120, 40);
    expect(pty.cols).toBe(120);
    expect(pty.rows).toBe(40);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npx vitest run tests/pty-manager.test.js`
Expected: FAIL — `PtyManager` not found

- [ ] **Step 3: Implement PtyManager**

Create `src/pty-manager.js`:

```javascript
import pty from 'node-pty';
import path from 'node:path';

export class PtyManager {
  constructor({ shell = null, args = [] } = {}) {
    this.shellPath = shell || process.env.SHELL || '/bin/sh';
    this.args = args;
    this.process = null;
    this.cols = 0;
    this.rows = 0;
    this._onData = null;
    this._onExit = null;
  }

  spawn(cols, rows) {
    this.cols = cols;
    this.rows = rows;

    this.process = pty.spawn(this.shellPath, this.args, {
      name: 'xterm-256color',
      cols,
      rows,
      cwd: process.cwd(),
      env: process.env,
    });

    this.process.onData((data) => {
      if (this._onData) this._onData(data);
    });

    this.process.onExit(({ exitCode, signal }) => {
      if (this._onExit) this._onExit(exitCode, signal);
    });

    return this.process;
  }

  onData(handler) {
    this._onData = handler;
  }

  onExit(handler) {
    this._onExit = handler;
  }

  write(data) {
    if (this.process) this.process.write(data);
  }

  resize(cols, rows) {
    this.cols = cols;
    this.rows = rows;
    if (this.process) this.process.resize(cols, rows);
  }

  get pid() {
    return this.process?.pid;
  }

  destroy() {
    if (this.process) {
      try {
        this.process.kill();
      } catch {
        // Already exited
      }
    }
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npx vitest run tests/pty-manager.test.js`
Expected: PASS

- [ ] **Step 5: Write test for onExit callback**

Add to `tests/pty-manager.test.js`:

```javascript
it('fires onExit when shell exits', async () => {
  pty = new PtyManager({ shell: '/bin/sh', args: ['-c', 'exit 42'] });

  const exitPromise = new Promise((resolve) => {
    pty.onExit((exitCode) => resolve(exitCode));
  });

  pty.spawn(80, 24);
  const code = await exitPromise;
  expect(code).toBe(42);
});
```

- [ ] **Step 6: Run all PTY manager tests**

Run: `npx vitest run tests/pty-manager.test.js`
Expected: All PASS

- [ ] **Step 7: Commit**

```bash
git add src/pty-manager.js tests/pty-manager.test.js
git commit -m "add PTY manager: spawn, resize, data/exit callbacks"
```

---

### Task 6: Discovery (Bonjour + QR Code)

**Files:**
- Create: `src/discovery.js`

This module is hard to unit test meaningfully (Bonjour requires network, QR writes to stdout), so we test it via integration in Task 8.

- [ ] **Step 1: Implement discovery module**

Create `src/discovery.js`:

```javascript
import Bonjour from 'bonjour-service';
import qrcode from 'qrcode-terminal';
import os from 'node:os';
import path from 'node:path';

export class Discovery {
  constructor({ port, code, salt, shell, host = '0.0.0.0', noQr = false, noBonjour = false }) {
    this.port = port;
    this.code = code;
    this.salt = salt;
    this.shell = path.basename(shell);
    this.host = host;
    this.noQr = noQr;
    this.noBonjour = noBonjour;
    this.bonjour = null;
    this.service = null;
  }

  start() {
    const ip = this._getLocalIp();
    const params = this.code ? `?code=${this.code}&salt=${this.salt}` : '';
    const url = `ws://${ip}:${this.port}${params}`;

    if (!this.noBonjour) {
      this.bonjour = new Bonjour();
      this.service = this.bonjour.publish({
        name: `terminal-thingy-${os.hostname()}`,
        type: 'terminal-thingy',
        port: this.port,
        txt: {
          salt: this.salt,
          shell: this.shell,
          hostname: os.hostname(),
        },
      });
    }

    return { ip, url };
  }

  printConnectionInfo(url, code) {
    console.log('');
    console.log('🔗 terminal-thingy streaming on local network');
    console.log('');

    if (!this.noQr) {
      qrcode.generate(url, { small: true }, (qr) => {
        const lines = qr.split('\n');
        const infoLines = code
          ? [`    PIN: ${code.slice(0, 3)} ${code.slice(3)}`, '', '    Scan QR or enter PIN in the app']
          : ['    No auth — open to local network', '', '    Scan QR to connect'];
        for (let i = 0; i < Math.max(lines.length, infoLines.length); i++) {
          const qrLine = lines[i] || '';
          const infoLine = infoLines[i - 1] || '';
          console.log(`  ${qrLine.padEnd(30)}${infoLine}`);
        }
        console.log('');
        console.log('  Waiting for connections...');
        console.log('');
      });
    } else {
      if (code) console.log(`  PIN: ${code.slice(0, 3)} ${code.slice(3)}`);
      console.log(`  URL: ${url}`);
      console.log('');
      console.log('  Waiting for connections...');
      console.log('');
    }
  }

  _getLocalIp() {
    const interfaces = os.networkInterfaces();
    for (const name of Object.keys(interfaces)) {
      for (const iface of interfaces[name]) {
        if (iface.family === 'IPv4' && !iface.internal) {
          return iface.address;
        }
      }
    }
    return '127.0.0.1';
  }

  stop() {
    if (this.service) {
      this.service.stop();
      this.service = null;
    }
    if (this.bonjour) {
      this.bonjour.destroy();
      this.bonjour = null;
    }
  }
}
```

- [ ] **Step 2: Verify module imports cleanly**

Run: `node -e "import('./src/discovery.js').then(() => console.log('OK'))"`
Expected: `OK`

- [ ] **Step 3: Commit**

```bash
git add src/discovery.js
git commit -m "add discovery module: Bonjour advertisement and QR code display"
```

---

### Task 7: CLI Entry Point + Orchestration

**Files:**
- Modify: `bin/terminal-thingy.js`
- Modify: `src/app.js`

- [ ] **Step 1: Implement CLI argument parsing**

Update `bin/terminal-thingy.js`:

```javascript
#!/usr/bin/env node
import { Command } from 'commander';
import { startApp } from '../src/app.js';

const program = new Command();

program
  .name('terminal-thingy')
  .description('Stream your terminal to your phone')
  .version('0.1.0')
  .option('--port <number>', 'WebSocket server port (default: random)', parseInt)
  .option('--host <address>', 'Bind address', '0.0.0.0')
  .option('--shell <command>', 'Shell to run (default: $SHELL)')
  .option('--no-qr', 'Skip printing QR code')
  .option('--no-bonjour', 'Skip mDNS advertisement')
  .option('--fps <number>', 'Max updates per second', parseInt, 30)
  .option('--scrollback <number>', 'Max scrollback lines', parseInt, 1000)
  .option('--no-auth', 'Disable token auth and encryption')
  .parse();

startApp(program.opts());
```

- [ ] **Step 2: Implement main orchestrator**

Update `src/app.js`:

```javascript
import { generateCode, generateSalt } from './auth.js';
import { PtyManager } from './pty-manager.js';
import { VirtualTerminal } from './virtual-terminal.js';
import { StreamServer } from './server.js';
import { Discovery } from './discovery.js';

export async function startApp(opts) {
  const shell = opts.shell || process.env.SHELL || '/bin/sh';
  const useAuth = opts.auth !== false;
  const code = useAuth ? generateCode() : null;
  const salt = useAuth ? generateSalt() : null;
  const fps = opts.fps || 30;
  const scrollbackLimit = opts.scrollback || 1000;

  // Get outer terminal size
  const cols = process.stdout.columns || 80;
  const rows = process.stdout.rows || 24;

  // Start WebSocket server
  const server = new StreamServer({
    port: opts.port || 0,
    host: opts.host || '0.0.0.0',
    auth: useAuth,
    code,
    salt,
  });

  const address = await server.start();

  // Start discovery
  const discovery = new Discovery({
    port: address.port,
    code,
    salt,
    shell,
    host: opts.host,
    noQr: opts.qr === false,
    noBonjour: opts.bonjour === false,
  });

  const { url } = discovery.start();
  discovery.printConnectionInfo(url, code);

  // Create virtual terminal
  const vt = new VirtualTerminal(cols, rows, scrollbackLimit);

  // Handle new client connections — send current state + scrollback
  server.onConnect((ws) => {
    server.send(ws, vt.getState());
    const scrollback = vt.getScrollbackBuffer();
    if (scrollback.length > 0) {
      server.send(ws, { type: 'scrollback', lines: scrollback });
    }
  });

  // Spawn PTY
  const ptyManager = new PtyManager({ shell });
  ptyManager.spawn(cols, rows);

  // Set stdin to raw mode
  if (process.stdin.isTTY) {
    process.stdin.setRawMode(true);
  }
  process.stdin.resume();

  // Proxy stdin → PTY
  process.stdin.on('data', (data) => {
    ptyManager.write(data);
  });

  // PTY output → stdout + virtual terminal
  ptyManager.onData((data) => {
    process.stdout.write(data);
    vt.write(data);
  });

  // Diff broadcast tick
  const tickInterval = Math.round(1000 / fps);
  const ticker = setInterval(() => {
    if (server.clientCount() === 0) return;

    // Collect scrollback first
    const newScrollback = vt.collectScrollback();
    if (newScrollback.length > 0) {
      server.broadcast({ type: 'scrollback', lines: newScrollback });
    }

    // Then send diff
    const diff = vt.getDiff();
    if (diff) {
      server.broadcast(diff);
    }
  }, tickInterval);

  // Handle terminal resize
  process.stdout.on('resize', () => {
    const newCols = process.stdout.columns;
    const newRows = process.stdout.rows;
    ptyManager.resize(newCols, newRows);
    vt.resize(newCols, newRows);
    if (server.clientCount() > 0) {
      server.broadcast({ type: 'resize', cols: newCols, rows: newRows });
      server.broadcast(vt.getState());
    }
  });

  // Cleanup function
  const cleanup = () => {
    clearInterval(ticker);
    if (process.stdin.isTTY) {
      process.stdin.setRawMode(false);
    }
    process.stdin.pause();
    discovery.stop();
    server.close();
    vt.destroy();
    ptyManager.destroy();
  };

  // Handle PTY exit
  ptyManager.onExit((exitCode) => {
    cleanup();
    process.exit(exitCode ?? 0);
  });

  // Handle signals
  const handleSignal = (signal) => {
    cleanup();
    ptyManager.destroy();
    process.exit(signal === 'SIGINT' ? 130 : 143);
  };

  process.on('SIGINT', () => handleSignal('SIGINT'));
  process.on('SIGTERM', () => handleSignal('SIGTERM'));

  // Handle uncaught errors — always restore terminal
  process.on('uncaughtException', (err) => {
    cleanup();
    console.error('Fatal error:', err.message);
    process.exit(1);
  });
}
```

- [ ] **Step 3: Verify CLI starts without errors**

Run: `node bin/terminal-thingy.js --help`
Expected: Prints help with all options listed

- [ ] **Step 4: Commit**

```bash
git add bin/terminal-thingy.js src/app.js
git commit -m "wire up CLI entry point and main orchestrator"
```

---

### Task 8: Integration Test

**Files:**
- Create: `tests/integration.test.js`

- [ ] **Step 1: Write integration test — basic connection and state**

Create `tests/integration.test.js`:

```javascript
import { describe, it, expect, afterEach } from 'vitest';
import WebSocket from 'ws';
import { generateCode, generateSalt, deriveKey, decrypt } from '../src/auth.js';
import { VirtualTerminal } from '../src/virtual-terminal.js';
import { StreamServer } from '../src/server.js';

describe('Integration: Server + VirtualTerminal', () => {
  let server;

  afterEach(async () => {
    if (server) await server.close();
  });

  it('new client receives full state on connect', async () => {
    const code = generateCode();
    const salt = generateSalt();
    const key = deriveKey(code, salt);

    const vt = new VirtualTerminal(80, 24, 100);
    await new Promise((resolve) => vt.terminal.write('$ hello world', resolve));

    server = new StreamServer({ port: 0, auth: true, code, salt });
    const address = await server.start();

    server.onConnect((ws) => {
      server.send(ws, vt.getState());
    });

    const ws = new WebSocket(`ws://127.0.0.1:${address.port}?code=${code}`);

    const message = await new Promise((resolve) => {
      ws.on('message', (data) => resolve(data.toString()));
    });

    const state = JSON.parse(decrypt(message, key));
    expect(state.type).toBe('state');
    expect(state.cols).toBe(80);
    expect(state.rows).toBe(24);
    // First row should contain "$ hello world"
    const firstRowText = state.cells[0].map((c) => c.char).join('').trimEnd();
    expect(firstRowText).toBe('$ hello world');

    ws.close();
    vt.destroy();
  });

  it('client receives diffs when terminal changes', async () => {
    const vt = new VirtualTerminal(80, 24, 100);
    server = new StreamServer({ port: 0, auth: false });
    const address = await server.start();

    server.onConnect((ws) => {
      server.send(ws, vt.getState());
    });

    const ws = new WebSocket(`ws://127.0.0.1:${address.port}`);
    await new Promise((resolve) => ws.on('open', resolve));

    // Consume initial state
    await new Promise((resolve) => ws.on('message', () => resolve()));

    // Write to virtual terminal and broadcast diff
    await new Promise((resolve) => vt.terminal.write('test', resolve));
    // Initialize diff tracking (first getDiff sets previous state)
    vt.getDiff();
    await new Promise((resolve) => vt.terminal.write(' output', resolve));
    const diff = vt.getDiff();
    expect(diff).not.toBeNull();
    server.broadcast(diff);

    const message = await new Promise((resolve) => {
      ws.on('message', (data) => resolve(data.toString()));
    });

    const parsed = JSON.parse(message);
    expect(parsed.type).toBe('diff');
    expect(parsed.changes.length).toBeGreaterThan(0);

    ws.close();
    vt.destroy();
  });

  it('rejected client does not receive messages', async () => {
    const code = '123456';
    const salt = generateSalt();

    server = new StreamServer({ port: 0, auth: true, code, salt });
    const address = await server.start();

    const ws = new WebSocket(`ws://127.0.0.1:${address.port}?code=wrong`);
    const closeCode = await new Promise((resolve) => ws.on('close', (c) => resolve(c)));
    expect(closeCode).toBe(4001);
    expect(server.clientCount()).toBe(0);
  });
});
```

- [ ] **Step 2: Run integration tests**

Run: `npx vitest run tests/integration.test.js`
Expected: All PASS

- [ ] **Step 3: Run full test suite**

Run: `npx vitest run`
Expected: All tests pass across all test files

- [ ] **Step 4: Commit**

```bash
git add tests/integration.test.js
git commit -m "add integration tests for server + virtual terminal"
```

---

### Task 9: Manual Smoke Test

No new files — this is a verification step.

- [ ] **Step 1: Run the CLI**

Run in a terminal:
```bash
node bin/terminal-thingy.js --no-bonjour
```

Expected:
- QR code is displayed
- PIN is displayed
- Shell prompt appears after the connection info
- Typing works normally
- Ctrl+C doesn't kill the wrapper (passes to inner shell)
- `exit` exits cleanly, terminal is restored to normal

- [ ] **Step 2: Test WebSocket connection with wscat**

In a second terminal (while CLI is running):
```bash
npx wscat -c "ws://127.0.0.1:<port>?code=<code>"
```

Replace `<port>` and `<code>` with values from the CLI output.

Expected: Receives encrypted messages (base64 strings). Verifies the server is broadcasting.

- [ ] **Step 3: Test --no-auth mode**

```bash
node bin/terminal-thingy.js --no-auth --no-bonjour
```

Connect with wscat:
```bash
npx wscat -c "ws://127.0.0.1:<port>"
```

Expected: Receives readable JSON messages — `state` on connect, then `diff` messages as you type.

- [ ] **Step 4: Final commit**

```bash
git add -A
git commit -m "terminal-thingy CLI v0.1.0 complete"
```
