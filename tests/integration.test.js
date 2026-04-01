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
