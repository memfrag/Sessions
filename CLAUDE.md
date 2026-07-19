# Sessions

A crash-resilient terminal multiplexer for macOS (SwiftUI). Workspaces in a
sidebar, terminal tabs in the detail pane. The headline property: terminal
sessions survive a UI crash because every PTY lives in a separate
`sessions-server` process; the app is a thin client.

## Build / test / lint

- **Build the app** with the scheme `Sessions (Debug)` (or `Sessions (Release)`) — NOT `Sessions`:
  `xcodebuild -project Sessions.xcodeproj -scheme "Sessions (Debug)" -configuration Debug build`
- **Package tests** (server core, real PTYs over a real socket):
  `swift test --package-path Packages/SessionsKit`
- **Lint**: `swiftlint` (curated `only_rules` set in `.swiftlint.yml`; not run as a build phase).
- Every Swift file starts with the header `//\n//  Copyright © <year> Apparata AB. All rights reserved.\n//`.

## Architecture

```
Sessions.app (SwiftUI)  ⇄  Unix socket  ⇄  sessions-server (launchd agent)
  emulator per tab          framed protocol    PTY + shell per session
  attach/detach/replay      JSON + raw bytes    scrollback ring buffer + state.json
```

- **`Packages/SessionsKit`** (local SPM package): `SessionsProtocol` (models,
  control messages, frame codec), `SessionsIPC` (Unix-socket connection +
  peer code-signature verification), `SessionsServerCore`
  (`ServerCore`/`SessionActor`/`PtyProcess`, ring buffer, `state.json`),
  `sessions-server` (executable, embedded at `Contents/MacOS/`), and
  `SessionsClient` (app-side client actor).
- **`Sessions/`** — the SwiftUI app. macOS code under `Sessions/macOS/`;
  shared/settings under `Sessions/All Platforms/`.
- The emulator is **headless**: server output is pushed in via `feed`, and
  user input / query responses come back out through a delegate. On attach
  the terminal is reset (RIS) and the server replays its scrollback ring;
  an `isReplaying` flag drops terminal→host egress during replay so
  re-parsed historical queries don't spew at the prompt.

## Terminal engine (libghostty)

The engine is **libghostty** via the `Lakr233/libghostty-spm` package
(prebuilt XCFramework — no Zig build), confined behind the
`TerminalEmulator` seam. `GhosttyEmulator` is the sole implementation
(SwiftTerm was fully removed). Key facts — see the `ghostty-backend` memory
for detail:

- **Config is validated as one blob**: a single invalid `keybind`/color/etc.
  line makes libghostty reject the WHOLE config and silently fall back to
  defaults (symptom: default colors, no padding). The shared
  `TerminalController` uses an EMPTY theme so `terminalConfiguration` colors
  aren't overridden.
- **Surface lifecycle**: libghostty only parses bytes once its render
  surface exists (dropped otherwise), but the surface persists across
  mount/unmount. `GhosttyEmulator` re-attaches once via `onSurfaceReady` so
  the server replays into a fresh surface.
- **Attention is engine-independent**: `TerminalStreamScanner` parses OSC
  0/2/7/9, BEL, and bracketed-paste mode (DECSET 2004) from the raw server
  stream for every session, so background/never-mounted tabs still drive
  badges (Claude status via OSC 9 `claude:*`, bell, title, cwd).
- **PTY size is reconciled after attach** — libghostty relays its grid size
  to the server PTY; a resize dropped during the async handshake would leave
  the PTY at a stale width and corrupt wrapped-line editing.
- libghostty's default **keybinds are cleared** so app shortcuts reach the
  menu; only copy/paste/select-all are re-added.
- Finder file drops are handled in AppKit on `TerminalContainerView`
  (registered on the selected tab only) and inserted as a bracketed paste.

## Development environment

- DEBUG builds spawn the embedded server directly (avoids stranding launchd
  registrations that point into DerivedData). `SESSIONS_USE_LAUNCHD=1` tests
  the launchd path; `SESSIONS_SERVER_SOCKET=/tmp/dev.sock` connects to an
  externally run server (`swift run --package-path Packages/SessionsKit sessions-server --socket /tmp/dev.sock`).
- **The server outlives app rebuilds.** Server-side changes don't take
  effect until the server restarts, and the embedded binary can lag the
  source. After changing server code, restart the server and confirm the new
  pid runs the new binary. The app auto-detects a build mismatch (server
  reports its Mach-O `LC_UUID` in `serverHello`) and shows a "Restart Server"
  banner.
- **Protocol**: `SessionsProtocol/ProtocolInfo.swift`. v2 added tolerant
  control decoding (unknown payloads → `.unknownMessage`), so additive
  messages don't need a version bump — a bump kills live sessions via the
  mismatch-restart flow.
- **Socket security**: UID check + peer code-signature verification
  (bidirectional). Raw socket probes from nc/python are rejected by design;
  test server behavior via the package tests.

## Gotchas

- **SwiftUI `Slider` is banned** — it triggers a fatal RenderBox
  `default.metallib` crash on macOS 26.4. Use `Stepper`/`Picker`.
- Settings scenes must apply `.appEnvironment(.default)` (or their
  `@Environment(AppSettings.self)` views crash).
- The main window is a single-instance `Window`, not a `WindowGroup`.
- pbxproj uses `PBXFileSystemSynchronizedRootGroup`: files on disk auto-join
  the target, so new files usually need no pbxproj edit. Xcode auto-normalizes
  manual pbxproj edits when the project is open.
- Never force-kill the server on connection-refused (it's merely starting) —
  only on handshake timeout / ignored restart. See `ServerManager.connectLoop`.

## Working conventions

- **Do not credit yourself in commits** — no self-attribution, no
  `Co-Authored-By`/"Generated with" trailers.
- **Verify UI changes by asking the user to look** — do not screencapture or
  use osascript to check the UI yourself.
- Match the surrounding code's style, comment density, and naming.
