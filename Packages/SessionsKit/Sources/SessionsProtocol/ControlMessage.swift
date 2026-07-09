//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import Foundation

/// Control-plane messages exchanged between the app and the session server.
///
/// Encoded as JSON inside a control frame. High-rate terminal I/O does not
/// use control messages; it travels in binary output/input frames.
public enum ControlMessage: Codable, Sendable, Equatable {

    // MARK: Handshake / server lifecycle

    case clientHello(protocolVersion: Int, appVersion: String)
    /// `buildID` is the server binary's Mach-O LC_UUID (from the running
    /// image), letting the app detect a server that predates the binary
    /// embedded in the current bundle. Optional: additive field.
    case serverHello(protocolVersion: Int, serverVersion: String, state: ServerState, buildID: String?)
    case protocolMismatch(serverProtocolVersion: Int)
    /// Server persists state and exits with code 1, so launchd relaunches
    /// the (possibly updated) binary.
    case restartServer
    /// Server persists state and exits with code 0, staying down.
    case shutdown

    // MARK: Workspace CRUD

    case createWorkspace(name: String, rootPath: String, startupCommand: String?, colorID: String?)
    case renameWorkspace(id: UUID, name: String)
    /// Edits the workspace's name, startup command, and color together
    /// (the edit sheet). `renameWorkspace` stays for quick renames.
    case updateWorkspace(id: UUID, name: String, startupCommand: String?, colorID: String?)
    case deleteWorkspace(id: UUID)
    case moveWorkspace(id: UUID, toIndex: Int)

    // MARK: Session (tab) CRUD

    /// Spawns a new session. The working directory is inherited from
    /// `inheritFromSessionID`'s foreground process when possible, falling
    /// back to the workspace root, then the home directory.
    case createSession(workspaceID: UUID, inheritFromSessionID: UUID?)
    case closeSession(id: UUID)
    /// Kills all shells and removes all tabs; workspaces remain.
    /// Used by "Quit and Stop All Sessions".
    case closeAllSessions
    case renameSession(id: UUID, customTitle: String?)
    /// Respawns the shell of a dead session.
    case restartSession(id: UUID)
    case moveSession(id: UUID, toIndex: Int)
    /// Moves a session to another workspace (drag a tab onto a sidebar
    /// row). A pure state move: the PTY, scrollback, and any attachment
    /// are untouched. `toIndex` nil appends at the end.
    case moveSessionToWorkspace(id: UUID, workspaceID: UUID, toIndex: Int?)

    // MARK: Busy check (close confirmation)

    case checkBusy(sessionID: UUID)
    /// Reply to `checkBusy`. Busy means the PTY's foreground process group
    /// is not the shell itself.
    case busyStatus(sessionID: UUID, isBusy: Bool)

    // MARK: Shell integration

    /// The client's terminal saw an OSC 7 working-directory report for a
    /// session (client → server). Used to make new-tab cwd inheritance
    /// precise; runtime-only, never persisted.
    case sessionCwdChanged(sessionID: UUID, path: String)

    // MARK: State sync (server → client)

    case stateChanged(ServerState)

    // MARK: Attachment & terminal control

    case attach(sessionID: UUID, cols: Int, rows: Int)
    case detach(sessionID: UUID)
    /// Sent in response to `attach`, followed by `replayBytes` bytes of
    /// scrollback in output frames, then `replayDone`.
    case attached(sessionID: UUID, isAlive: Bool, replayBytes: Int)
    case replayDone(sessionID: UUID)
    case resize(sessionID: UUID, cols: Int, rows: Int)
    case sessionExited(sessionID: UUID, exitCode: Int32?)

    // MARK: Errors

    case error(code: ErrorCode, message: String)

    // MARK: Decoder fallback

    /// Never sent intentionally. Produced by `FrameDecoder` when a control
    /// frame's payload does not decode (a message from a newer peer, or
    /// corruption). Handlers ignore it, which makes additive protocol
    /// changes non-breaking.
    case unknownMessage
}

public enum ErrorCode: String, Codable, Sendable {
    case unknownWorkspace
    case unknownSession
    case spawnFailed
    case detachedByOtherClient
    case invalidMessage
}
