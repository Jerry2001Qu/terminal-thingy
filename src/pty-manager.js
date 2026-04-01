import pty from 'node-pty';

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
