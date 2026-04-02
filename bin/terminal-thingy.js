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
  .option('--name <name>', 'Session name shown on phone (default: folder name)')
  .option('--no-auth', 'Disable token auth and encryption')
  .option('--reset-pin', 'Generate a new PIN for this device')
  .option('--verbose', 'Log connection attempts to stderr')
  .parse();

startApp(program.opts());
