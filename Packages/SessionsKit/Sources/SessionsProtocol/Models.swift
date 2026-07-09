//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import Foundation

/// A terminal session (tab) belonging to a workspace.
///
/// Layout fields (`id`, `customTitle`) are persisted by the server; runtime
/// fields (`isAlive`, `exitCode`) reflect the live process state and reset to
/// "dead, not exited" when the server restarts.
public struct SessionInfo: Codable, Sendable, Hashable, Identifiable {

    public let id: UUID

    /// User-assigned title, if the user renamed the tab. Overrides any
    /// title reported by the shell.
    public var customTitle: String?

    /// Whether a shell process is currently running for this session.
    public var isAlive: Bool

    /// Exit code of the most recent shell, if it has exited.
    ///
    /// `isAlive == false && exitCode == nil` means the session has never been
    /// started since the server booted (e.g. after a reboot); clients
    /// auto-restart such sessions when they are selected. A non-nil exit code
    /// means the shell exited and the client shows a restart overlay instead.
    public var exitCode: Int32?

    public init(id: UUID = UUID(), customTitle: String? = nil, isAlive: Bool = false, exitCode: Int32? = nil) {
        self.id = id
        self.customTitle = customTitle
        self.isAlive = isAlive
        self.exitCode = exitCode
    }
}

/// A workspace groups a set of terminal sessions (tabs) under a name and a
/// root working directory.
public struct Workspace: Codable, Sendable, Hashable, Identifiable {

    public let id: UUID

    public var name: String

    /// Absolute path to the workspace's root directory.
    public var rootPath: String

    /// Command typed into every NEW tab of this workspace right after its
    /// shell spawns (e.g. auto-starting a dev server). Not run on session
    /// restarts or when reviving dormant sessions after a server reboot.
    public var startupCommand: String?

    /// ID of a predefined accent color for the workspace, purely cosmetic.
    /// Rendering is the client's business; the server just stores the ID.
    public var colorID: String?

    /// The sessions (tabs) of the workspace, in tab order.
    public var sessions: [SessionInfo]

    public init(
        id: UUID = UUID(),
        name: String,
        rootPath: String,
        startupCommand: String? = nil,
        colorID: String? = nil,
        sessions: [SessionInfo] = []
    ) {
        self.id = id
        self.name = name
        self.rootPath = rootPath
        self.startupCommand = startupCommand
        self.colorID = colorID
        self.sessions = sessions
    }
}

/// Full snapshot of the server's workspace/session state, in sidebar order.
public struct ServerState: Codable, Sendable, Equatable {

    public var workspaces: [Workspace]

    public init(workspaces: [Workspace] = []) {
        self.workspaces = workspaces
    }

    public func workspace(withID id: Workspace.ID) -> Workspace? {
        workspaces.first { $0.id == id }
    }

    public func session(withID id: SessionInfo.ID) -> (workspace: Workspace, session: SessionInfo)? {
        for workspace in workspaces {
            if let session = workspace.sessions.first(where: { $0.id == id }) {
                return (workspace, session)
            }
        }
        return nil
    }
}
