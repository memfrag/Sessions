
# Sessions

A terminal multiplexer for macOS. Workspaces (name + root directory) in a
sidebar, terminal tabs in the detail pane, rendered with
[SwiftTerm](https://github.com/migueldeicaza/SwiftTerm).

## Architecture

The headline feature is **crash resilience**: terminal sessions survive if
the UI crashes. All PTYs live in a separate session-server process
(tmux-style client/server); the app is a thin client.

```
Sessions.app (SwiftUI)  ⇄  Unix socket  ⇄  sessions-server (launchd agent)
  TerminalView per tab      framed protocol     PTY + shell per session
  attach/detach/replay      JSON + raw bytes    2 MiB scrollback ring buffer
                                                state.json (layout persistence)
```

- **`Packages/SessionsKit`** — local Swift package:
  - `SessionsProtocol` — models, control messages, frame codec (shared).
  - `SessionsIPC` — Unix-domain-socket connection/listener (DispatchSource).
  - `SessionsServerCore` — `ServerCore`/`SessionActor`/`PtyProcess`
    (forkpty), ring buffer, state store. Unit-tested headless.
  - `sessions-server` — the server executable, embedded in the app bundle
    at `Contents/MacOS/`, managed as a launchd agent via `SMAppService`
    (plist in `Contents/Library/LaunchAgents/`).
  - `SessionsClient` — the app-side client actor.
- **`Sessions/`** — the SwiftUI app.

Server lifecycle: launchd starts the server at login and relaunches it on
crash (`KeepAlive.SuccessfulExit = false`). ⌘Q only detaches — shells keep
running; “Quit and Stop All Sessions” (⌥⌘Q) stops everything. If the server
itself dies, sessions die with it (like tmux), but the workspace/tab layout
persists and dead sessions respawn their shell on selection.

## Development

- DEBUG builds spawn the embedded server directly instead of registering a
  launchd agent (avoids stranding registrations that point into
  DerivedData). Set `SESSIONS_USE_LAUNCHD=1` to test the launchd path.
- `SESSIONS_SERVER_SOCKET=/tmp/dev.sock` makes the app connect to an
  externally managed server, e.g.:
  `swift run --package-path Packages/SessionsKit sessions-server --socket /tmp/dev.sock`
- Package tests: `swift test --package-path Packages/SessionsKit`
  (includes end-to-end tests over a real socket with real PTYs).
- Crash-resilience smoke test: run something in a tab, `kill -9` the app,
  relaunch — the process keeps running and the scrollback replays.

## License

See the LICENSE file for licensing information.
