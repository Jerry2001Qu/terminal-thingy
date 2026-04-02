import { WebSocketServer } from 'ws';
import { URL } from 'node:url';
import { encrypt, decrypt, deriveKey } from './auth.js';

export class StreamServer {
  constructor({ port = 0, host = '0.0.0.0', auth = true, code = null, salt = null, verbose = false }) {
    this.port = port;
    this.host = host;
    this.auth = auth;
    this.code = code;
    this.salt = salt;
    this.key = auth && code && salt ? deriveKey(code, salt) : null;
    this.wss = null;
    this.clients = new Set();

    this.verbose = verbose;

    // Rate limiting
    this.failedAttempts = new Map(); // ip -> { count, lockedUntil }
    this.globalFailCount = 0;
    this.globalLockedUntil = 0;
    this.globalResetTimer = null;
  }

  _log(msg, { force = false } = {}) {
    if (force || this.verbose) {
      process.stderr.write(`[terminal-thingy] ${msg}\n`);
    }
  }

  _checkRateLimit(ip) {
    const now = Date.now();

    // Global lockout
    if (this.globalLockedUntil > now) {
      const secs = Math.ceil((this.globalLockedUntil - now) / 1000);
      this._log(`Connection from ${ip} — rejected (global lockout, ${secs}s remaining)`);
      return false;
    }

    // Per-IP lockout
    const record = this.failedAttempts.get(ip);
    if (record && record.lockedUntil > now) {
      const secs = Math.ceil((record.lockedUntil - now) / 1000);
      this._log(`Connection from ${ip} — blocked (locked for ${secs}s)`);
      return false;
    }

    return true;
  }

  _recordFailure(ip) {
    const now = Date.now();
    const record = this.failedAttempts.get(ip) || { count: 0, lockedUntil: 0 };
    record.count++;

    // Per-IP: lock out after 5 failures with exponential backoff
    if (record.count >= 5) {
      const backoff = Math.min(30000 * Math.pow(2, record.count - 5), 300000); // 30s -> 5min cap
      record.lockedUntil = now + backoff;
      this._log(`Connection from ${ip} — failed auth (attempt ${record.count}, locked for ${Math.round(backoff / 1000)}s)`);
    } else {
      this._log(`Connection from ${ip} — failed auth (attempt ${record.count})`);
    }
    this.failedAttempts.set(ip, record);

    // Global: lock all connections after 10 failures in a rolling window
    this.globalFailCount++;
    if (this.globalFailCount >= 10) {
      this.globalLockedUntil = now + 60000;
      this.globalFailCount = 0;
      this._log('Too many failed attempts — all connections locked for 60s', { force: true });
    }

    // Reset global counter every 60s
    if (!this.globalResetTimer) {
      this.globalResetTimer = setTimeout(() => {
        this.globalFailCount = 0;
        this.globalResetTimer = null;
      }, 60000);
      this.globalResetTimer.unref();
    }
  }

  _recordSuccess(ip) {
    this.failedAttempts.delete(ip);
    this._log(`Connection from ${ip} — authenticated`);
  }

  start() {
    return new Promise((resolve, reject) => {
      this.wss = new WebSocketServer({ port: this.port, host: this.host });

      this.wss.on('listening', () => {
        resolve(this.wss.address());
      });

      this.wss.on('error', reject);

      this.wss.on('connection', (ws, req) => {
        const ip = req.socket.remoteAddress;

        if (this.auth) {
          if (!this._checkRateLimit(ip)) {
            ws.close(4029, 'Rate limited');
            return;
          }

          const url = new URL(req.url, `http://${req.headers.host}`);
          const clientCode = url.searchParams.get('code');
          if (clientCode !== this.code) {
            this._recordFailure(ip);
            ws.close(4001, 'Invalid code');
            return;
          }

          this._recordSuccess(ip);
        }

        this.clients.add(ws);
        ws.on('close', () => this.clients.delete(ws));
        ws.on('error', () => this.clients.delete(ws));

        ws.on('message', (raw) => {
          try {
            const text = raw.toString();
            const json = this.key ? decrypt(text, this.key) : text;
            const msg = JSON.parse(json);
            if (msg.type === 'input' && typeof msg.data === 'string') {
              if (this._onInput) this._onInput(msg.data);
            }
            if (msg.type === 'resize' && typeof msg.cols === 'number' && typeof msg.rows === 'number') {
              const cols = Math.max(10, Math.min(500, msg.cols));
              const rows = Math.max(3, Math.min(200, msg.rows));
              if (this._onResize) this._onResize(cols, rows);
            }
          } catch {
            // Invalid message, ignore
          }
        });

        if (this._onConnect) this._onConnect(ws);
      });
    });
  }

  onConnect(handler) {
    this._onConnect = handler;
  }

  onInput(handler) {
    this._onInput = handler;
  }

  onResize(handler) {
    this._onResize = handler;
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
        client.close(4000, 'Session ended');
      }
      this.wss.close(resolve);
    });
  }
}
