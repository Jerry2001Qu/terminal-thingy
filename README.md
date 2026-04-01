# terminal-thingy

Stream your terminal to your phone as a read-only second screen.

## What it does

Run the CLI on your laptop, and your terminal appears on your iPhone over local WiFi. No setup beyond scanning a QR code.

Good for:
- Monitoring long-running tasks without keeping your laptop screen on
- Watching Claude Code run while you do something else
- Keeping an eye on builds from across the room

Your phone is a viewer, not a controller. Terminal input stays on your laptop.

## Quick Start

```
npx terminal-thingy
```

This starts the server, prints a QR code and a PIN. Open the iOS app, scan the QR code (or enter the PIN manually), and your terminal starts streaming.

## CLI Options

| Option | Description | Default |
|---|---|---|
| `--port <number>` | WebSocket server port | random |
| `--host <address>` | Bind address | `0.0.0.0` |
| `--shell <command>` | Shell to run | `$SHELL` |
| `--no-qr` | Skip printing QR code | — |
| `--no-bonjour` | Skip mDNS advertisement | — |
| `--fps <number>` | Max updates per second | `30` |
| `--scrollback <number>` | Max scrollback lines | `1000` |
| `--no-auth` | Disable token auth and encryption | — |
| `--reset-pin` | Generate a new PIN for this device | — |

## iOS App

Coming soon to TestFlight.

To build from source:

1. Install xcodegen: `brew install xcodegen`
2. `cd ios && xcodegen generate`
3. Open `TerminalThingy.xcodeproj` in Xcode
4. Set your signing team in project settings
5. Build and run on your device

## How it works

- The CLI wraps your shell in a PTY and maintains a headless virtual terminal (xterm-headless)
- Screen state is diffed and streamed over WebSocket at up to 30fps
- The iOS app discovers the server via Bonjour (mDNS) or by scanning the QR code
- All traffic is AES-256-GCM encrypted by default
- Device pairing: enter the PIN once, and the app remembers it for future sessions

## Requirements

- CLI: Node.js 18+
- iOS app: iOS 16+, iPhone
- Both devices on the same WiFi network

## Security

- All traffic encrypted by default (AES-256-GCM)
- PIN-based device pairing
- Local network only — no data leaves your WiFi
- Use `--no-auth` to disable for trusted networks

## License

MIT
