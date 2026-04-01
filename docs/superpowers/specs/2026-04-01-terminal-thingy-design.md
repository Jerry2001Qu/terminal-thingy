# terminal-thingy Design Spec

Stream your terminal to your phone as a read-only second screen over local WiFi.

## System Overview

Two components:

1. **`terminal-thingy` CLI** — Node.js package (`npx terminal-thingy`). Wraps the user's shell in a PTY, maintains a headless virtual terminal, serves screen state over WebSocket.
2. **`Terminal Thingy` iOS app** — Native Swift/SwiftUI. Discovers sessions via Bonjour or QR code, connects over WebSocket, renders the terminal grid.

## Data Flow

```
User types → outer terminal → CLI stdin → PTY → shell process
                                                    │
                                              PTY output
                                                    │
                                    ┌───────────────┤
                                    ↓               ↓
                              CLI stdout     xterm-headless
                             (to laptop)     (virtual term)
                                                    │
                                              screen state
                                                    │
                                            AES encrypt
                                                    │
                                              WebSocket
                                                    │
                                            AES decrypt
                                                    │
                                              iOS app
                                             (renderer)
```

## CLI Architecture

### Startup Sequence

1. Save original terminal state (for cleanup)
2. Spawn PTY with `$SHELL`, inheriting `$TERM`, `$COLORTERM`, `$LANG`
3. Create `xterm-headless` instance matching outer terminal dimensions
4. Generate auth token and derive 6-digit PIN
5. Start WebSocket server on configured port (default: random available)
6. Advertise via Bonjour as `_terminal-thingy._tcp`
7. Print QR code (encoding `ws://<IP>:<port>?token=<token>`) and PIN to terminal
8. Set outer terminal to raw mode
9. Begin proxying stdin → PTY and PTY → stdout + xterm-headless

### Diff Engine

Each tick (configurable, default ~33ms / 30fps):

1. Read current screen state from `xterm-headless`
2. Compare against previous snapshot
3. If changes exist, produce a diff (changed cells by row)
4. Encrypt and broadcast to all connected WebSocket clients
5. Store previous snapshot for next comparison

### Signal Handling

- `SIGWINCH` → resize PTY + `xterm-headless`, send `resize` + full `state` to clients
- `SIGINT` / `SIGTERM` → cleanup and exit
- Child process exit → restore terminal, cleanup, propagate exit code

### Cleanup (on exit, crash, or signal)

- Restore original terminal state
- Close WebSocket server
- Remove Bonjour advertisement
- Exit with child's exit code

### Dependencies

- `node-pty` — PTY allocation and management
- `xterm-headless` — headless terminal emulator (xterm.js project)
- `ws` — WebSocket server
- `bonjour-service` — mDNS advertisement
- `qrcode-terminal` — QR code rendering in terminal

### CLI Options

| Option | Default | Description |
|--------|---------|-------------|
| `--port <n>` | Random available | WebSocket server port |
| `--host <addr>` | `0.0.0.0` | Bind address |
| `--shell <cmd>` | `$SHELL` | Shell or command to run |
| `--no-qr` | false | Skip printing QR code |
| `--no-bonjour` | false | Skip mDNS advertisement |
| `--fps <n>` | 30 | Max updates per second |
| `--scrollback <n>` | 1000 | Max scrollback lines retained |
| `--no-auth` | false | Disable token auth and encryption |

## WebSocket Protocol

All messages are JSON. Payloads are AES-256-GCM encrypted (authenticated encryption) using the auth token as key derivation input via HKDF (unless `--no-auth`). Communication is server→client only (read-only).

### Message Types

#### `state` — Full screen state

Sent on: initial connection, resize, periodic recovery.

```json
{
  "type": "state",
  "cols": 120,
  "rows": 24,
  "cells": [[{"char": "h", "fg": "#fff", "bg": "#000", "bold": false, "italic": false, "underline": false}, ...], ...],
  "cursorX": 5,
  "cursorY": 12
}
```

#### `diff` — Incremental update

Sent on: each render tick when changes exist.

```json
{
  "type": "diff",
  "changes": [
    {"row": 5, "col": 0, "cells": [{"char": "$", "fg": "#0f0", "bg": "#000", "bold": false, "italic": false, "underline": false}, ...]}
  ],
  "cursorX": 2,
  "cursorY": 5
}
```

#### `scrollback` — History lines

Sent when lines scroll off the top of the terminal.

```json
{
  "type": "scrollback",
  "lines": [[{"char": "o", "fg": "#fff", "bg": "#000", "bold": false, "italic": false, "underline": false}, ...]]
}
```

#### `resize` — Terminal dimensions changed

Sent when the laptop terminal is resized, followed by a full `state` message.

```json
{
  "type": "resize",
  "cols": 80,
  "rows": 24
}
```

### Throttling

Diffs are batched at the configured FPS rate. Rapid output (e.g. `cat` a large file) does not flood the WebSocket — only the latest state after each batch window is sent.

### Reconnection

On reconnect, the client sends the auth token. The server responds with a full `state` message plus the scrollback buffer. The client is immediately caught up.

## Security

### Auth (default on, `--no-auth` to disable)

1. CLI generates a random token on startup
2. A 6-digit PIN is derived from the token for manual entry
3. QR code embeds the full token in the WebSocket URL
4. On WebSocket handshake, client must provide the token
5. Server rejects connections without a valid token

### Encryption (default on, `--no-auth` to disable)

1. The auth token is used as input to HKDF to derive an AES-256 key
2. All WebSocket payloads are AES-256-GCM encrypted (authenticated encryption)
3. Both sides have the token (from QR scan or PIN entry) and can encrypt/decrypt
4. Data on the wire is meaningless without the token

### Startup Display

```
🔗 terminal-thingy streaming on local network

  ┌──────────────┐
  │  QR CODE     │    PIN: 847 291
  │  HERE        │
  │              │    Scan QR or enter PIN in the app
  └──────────────┘

  Waiting for connections...
```

## iOS App Architecture

### Discovery View (launch screen)

- Bonjour browser lists discovered `_terminal-thingy._tcp` sessions
- Each entry shows: hostname, shell name, port
- QR scan button opens camera, parses `ws://` URL with embedded token
- Tapping a Bonjour entry prompts for the 6-digit PIN

### Terminal View (main screen)

**Renderer:** Core Text-based custom view for monospaced character rendering with per-cell color and attribute control. SwiftUI wraps the overall view structure.

**Fit-to-width:** Font size is calculated as `screenWidth / cols`. When the server sends a `resize` message with new dimensions, the font size recalculates and the grid re-renders.

**Scrollback behavior:**
- Default: pinned to live view (bottom of output)
- Swipe up: enter scrollback mode, browse history independently
- "New output" indicator appears when new content arrives while scrolled up
- Tap status bar or "Live" button: snap back to live view

**Orientation:**
- Portrait: fit-to-width, smaller text
- Landscape: fit-to-width, more readable text

### Connection Management

- Auto-reconnect on WebSocket drop with exponential backoff (1s, 2s, 4s... max 30s)
- On reconnect: re-authenticate, receive full state + scrollback, seamlessly resume
- Connection status indicator: connected / reconnecting / session ended

### Settings

- Theme: dark (default) / light
- Keep screen awake: on (default) / off

## Error Handling & Edge Cases

### Network

- **Phone loses WiFi:** WebSocket drops → auto-reconnect with backoff. Full state resync on reconnect.
- **Laptop sleeps:** WebSocket drops → same reconnect flow. Bonjour re-advertises on wake.
- **Port conflict (with `--port`):** Fail immediately with clear error message.

### Multiple Clients

Any number of phones can connect simultaneously. Server broadcasts the same diffs to all. No extra overhead beyond the WebSocket connection per client.

### Rapid Output

Throttled to configured FPS. Virtual terminal processes everything internally, but only the latest state is sent per tick window.

### Shell Exit

- Inner shell exits → CLI restores terminal, closes server, removes Bonjour, exits with shell's exit code.
- Phone sees WebSocket close → shows "Session ended" screen with option to return to discovery.

### Terminal Integrity

- Outer terminal set to raw mode on startup, original state saved
- On any exit path (normal, crash, SIGTERM): terminal state restored
- PTY inherits environment faithfully (`$TERM`, `$COLORTERM`, `$LANG`, etc.)
- Exit code of inner shell propagated as CLI's exit code
- `SIGWINCH` forwarded to PTY so inner programs resize correctly

## Testing Strategy

### CLI (Node.js)

- Unit: diff engine correctness (given two states, produce correct diff)
- Unit: token generation and AES encryption/decryption round-trip
- Integration: spawn CLI, connect WebSocket client, verify state messages
- Integration: connect without token, verify rejection
- Integration: resize PTY, verify resize + state messages sent
- Manual: run with Claude Code, verify terminal behaves normally

### iOS App

- Unit: terminal grid renderer layout math
- Unit: decryption and token handling
- Unit: font size calculation (screen width / cols)
- UI: mock WebSocket, verify rendering and scrollback
- Manual: connect to real CLI session, verify colors, full-screen apps, resize

### End-to-End

- Connect via QR, verify live output
- Kill WiFi on phone, restore, verify reconnect and state recovery
- Resize laptop terminal, verify phone updates
- Full-screen app (vim, htop), verify rendering
- Long-running output (tail -f), verify scrollback and "new output" indicator
