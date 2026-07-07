//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import Foundation

public enum SessionsProtocolInfo {

    /// Bump on any incompatible wire-protocol change. A mismatch during the
    /// handshake makes the app request a server restart, which kills live
    /// sessions (documented, acceptable).
    public static let version = 1
}

/// Canonical file locations shared by app and server.
public enum SessionsServerPaths {

    /// Environment variable that overrides the socket path (used in DEBUG
    /// builds to talk to a manually launched dev server).
    public static let socketEnvironmentVariable = "SESSIONS_SERVER_SOCKET"

    public static func applicationSupportDirectory() -> URL {
        URL.applicationSupportDirectory.appending(path: "Sessions", directoryHint: .isDirectory)
    }

    public static func defaultSocketPath() -> String {
        applicationSupportDirectory().appending(path: "server.sock").path(percentEncoded: false)
    }

    public static func defaultStatePath() -> String {
        applicationSupportDirectory().appending(path: "state.json").path(percentEncoded: false)
    }

    /// The socket path to use, honoring the environment override.
    public static func resolvedSocketPath(environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        environment[socketEnvironmentVariable] ?? defaultSocketPath()
    }
}
