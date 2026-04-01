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

  it('fires onExit when shell exits', async () => {
    pty = new PtyManager({ shell: '/bin/sh', args: ['-c', 'exit 42'] });

    const exitPromise = new Promise((resolve) => {
      pty.onExit((exitCode) => resolve(exitCode));
    });

    pty.spawn(80, 24);
    const code = await exitPromise;
    expect(code).toBe(42);
  });
});
