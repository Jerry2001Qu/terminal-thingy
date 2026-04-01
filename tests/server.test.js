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
    const { deriveKey, decrypt } = await import('../src/auth.js');
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
});
