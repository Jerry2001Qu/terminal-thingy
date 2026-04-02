import { PtyManager } from './pty-manager.js';
import { VirtualTerminal } from './virtual-terminal.js';
import { StreamServer } from './server.js';
import { Discovery } from './discovery.js';
import { loadOrCreateConfig, resetPin } from './config.js';

export async function startApp(opts) {
  const shell = opts.shell || process.env.SHELL || '/bin/sh';
  const useAuth = opts.auth !== false;
  let deviceId = null;
  let code = null;
  let salt = null;

  if (useAuth) {
    const config = opts.resetPin ? resetPin() : loadOrCreateConfig();
    deviceId = config.deviceId;
    code = config.pin;
    salt = config.salt;
  }
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

  let address;
  try {
    address = await server.start();
  } catch (err) {
    if (err.code === 'EADDRINUSE') {
      console.error(`Error: port ${opts.port} is already in use. Try a different port or omit --port to use a random one.`);
    } else {
      console.error(`Error starting server: ${err.message}`);
    }
    process.exit(1);
  }

  // Start discovery
  const discovery = new Discovery({
    port: address.port,
    code,
    salt,
    deviceId,
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
    // Send scrollback in chunks of 100 lines to avoid exceeding message size limits
    for (let i = 0; i < scrollback.length; i += 100) {
      server.send(ws, { type: 'scrollback', lines: scrollback.slice(i, i + 100) });
    }
  });

  server.onInput((data) => {
    ptyManager.write(data);
  });

  server.onResize((cols, rows) => {
    ptyManager.resize(cols, rows);
    vt.resize(cols, rows);
    // Broadcast resize immediately so clients know dimensions changed
    server.broadcast({ type: 'resize', cols, rows });
    // Delay state broadcast to let the shell redraw at the new size
    setTimeout(() => {
      server.broadcast(vt.getState());
    }, 100);
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
  const cleanup = async () => {
    clearInterval(ticker);
    if (process.stdin.isTTY) {
      process.stdin.setRawMode(false);
    }
    process.stdin.pause();
    discovery.stop();
    await server.close();
    vt.destroy();
    ptyManager.destroy();
  };

  // Handle PTY exit
  ptyManager.onExit(async (exitCode) => {
    await cleanup();
    process.exit(exitCode ?? 0);
  });

  // Handle signals
  const handleSignal = async (signal) => {
    await cleanup();
    ptyManager.destroy();
    process.exit(signal === 'SIGINT' ? 130 : 143);
  };

  process.on('SIGINT', () => handleSignal('SIGINT'));
  process.on('SIGTERM', () => handleSignal('SIGTERM'));
  process.on('SIGHUP', () => handleSignal('SIGHUP'));

  // Handle uncaught errors — always restore terminal
  process.on('uncaughtException', (err) => {
    cleanup();
    console.error('Fatal error:', err.message);
    process.exit(1);
  });
}
