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
        client.close(4000, 'Session ended');
      }
      this.wss.close(resolve);
    });
  }
}
