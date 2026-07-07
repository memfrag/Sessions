//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import Foundation
import SessionsClient
import SessionsProtocol

/// Runtime registry of terminal session controllers, keyed by session ID.
///
/// Controllers are created lazily on first request, attach immediately, and
/// are kept alive here so SwiftUI view churn never drops an attachment.
@MainActor
final class TerminalSessionRegistry {

    private var controllers: [SessionInfo.ID: TerminalSessionController] = [:]

    private let client: SessionServerClient

    init(client: SessionServerClient) {
        self.client = client
    }

    /// Returns the controller for a session, creating and attaching it
    /// if needed.
    func controller(for sessionID: SessionInfo.ID) -> TerminalSessionController {
        if let controller = controllers[sessionID] {
            return controller
        }
        let controller = TerminalSessionController(sessionID: sessionID, client: client)
        controllers[sessionID] = controller
        controller.attach()
        return controller
    }

    func controllerIfExists(for sessionID: SessionInfo.ID) -> TerminalSessionController? {
        controllers[sessionID]
    }

    /// Re-attaches every live controller. Called after a reconnect; the
    /// server replays scrollback into each terminal.
    func reattachAll() {
        for controller in controllers.values {
            controller.attach()
        }
    }

    /// Mirrors server state into controllers and drops controllers for
    /// sessions that no longer exist.
    func sync(with state: ServerState) {
        var seen = Set<SessionInfo.ID>()
        for workspace in state.workspaces {
            for session in workspace.sessions {
                seen.insert(session.id)
                controllers[session.id]?.applyInfo(session)
            }
        }
        for (id, controller) in controllers where !seen.contains(id) {
            controller.detach()
            controllers[id] = nil
        }
    }

    func noteExited(sessionID: SessionInfo.ID, exitCode: Int32?) {
        controllers[sessionID]?.noteExited(exitCode: exitCode)
    }
}
