//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import Foundation
import OSLog
import SessionsProtocol

/// Persists the server's workspace/session layout as JSON.
///
/// Runtime fields (`isAlive`, `exitCode`) are stripped on save so a freshly
/// booted server always loads sessions as "dead, never started", which makes
/// clients auto-restart them on selection.
struct StateStore {

    private static let logger = Logger(subsystem: "io.apparata.Sessions", category: "StateStore")

    let path: String

    func load() -> ServerState {
        do {
            let data = try Data(contentsOf: URL(filePath: path))
            var state = try JSONDecoder().decode(ServerState.self, from: data)
            state = Self.strippingRuntimeFields(state)
            return state
        } catch CocoaError.fileReadNoSuchFile {
            return ServerState()
        } catch {
            Self.logger.error("Failed to load state: \(error)")
            return ServerState()
        }
    }

    func save(_ state: ServerState) {
        do {
            let directory = (path as NSString).deletingLastPathComponent
            try FileManager.default.createDirectory(
                atPath: directory,
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(Self.strippingRuntimeFields(state))
            try data.write(to: URL(filePath: path), options: .atomic)
        } catch {
            Self.logger.error("Failed to save state: \(error)")
        }
    }

    private static func strippingRuntimeFields(_ state: ServerState) -> ServerState {
        var stripped = state
        for workspaceIndex in stripped.workspaces.indices {
            for sessionIndex in stripped.workspaces[workspaceIndex].sessions.indices {
                stripped.workspaces[workspaceIndex].sessions[sessionIndex].isAlive = false
                stripped.workspaces[workspaceIndex].sessions[sessionIndex].exitCode = nil
            }
        }
        return stripped
    }
}
