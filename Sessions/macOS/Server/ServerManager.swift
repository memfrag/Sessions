//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import AppKit
import Foundation
import Observation
import OSLog
import ServiceManagement
import SessionsClient
import SessionsIPC
import SessionsProtocol

/// Owns the connection to the session server: connects with retry/backoff,
/// launches the embedded server if none is running, reconnects after a
/// server restart, and forwards server events to the app.
///
/// - Note: M2 launches the embedded `sessions-server` directly when the
///   socket is not answering. M3 replaces launching with SMAppService
///   (launchd agent) registration; the connect/reconnect logic stays.
@Observable @MainActor
final class ServerManager {

    private static let logger = Logger(subsystem: "io.apparata.Sessions", category: "ServerManager")

    enum Status: Equatable {
        case idle
        case connecting
        case connected
        /// The launchd agent needs user approval in System Settings.
        case needsApproval
        case failed(String)
    }

    /// How the server process is brought up.
    ///
    /// - `launchdAgent`: SMAppService registration; launchd starts the server
    ///   at login and relaunches it if it crashes. Production behavior.
    /// - `directSpawn`: the app spawns the embedded binary directly. Default
    ///   in DEBUG builds to avoid stranding launchd registrations that point
    ///   into DerivedData. Opt into launchd with `SESSIONS_USE_LAUNCHD=1`.
    /// - `external`: `SESSIONS_SERVER_SOCKET` is set; a dev server is
    ///   managed manually (e.g. `swift run sessions-server --socket …`).
    private enum LaunchStrategy {
        case launchdAgent
        case directSpawn
        case external
    }

    private(set) var status: Status = .idle

    let client = SessionServerClient()

    var onStateChanged: ((ServerState) -> Void)?

    var onSessionExited: ((UUID, Int32?) -> Void)?

    /// Called after every successful (re)connect, once the initial state has
    /// been delivered. Used to re-attach visible terminals and replay
    /// scrollback — the crash-recovery path.
    var onConnected: (() -> Void)?

    private var connectTask: Task<Void, Never>?

    private var eventTask: Task<Void, Never>?

    private var didLaunchServer = false

    private let socketPath = SessionsServerPaths.resolvedSocketPath()

    private static let agentPlistName = "io.apparata.Sessions.SessionServer.plist"

    private static let agentLabel = "io.apparata.Sessions.SessionServer"

    private let agentService = SMAppService.agent(plistName: ServerManager.agentPlistName)

    private var strategy: LaunchStrategy {
        let environment = ProcessInfo.processInfo.environment
        if environment[SessionsServerPaths.socketEnvironmentVariable] != nil {
            return .external
        }
        #if DEBUG
        return environment["SESSIONS_USE_LAUNCHD"] == "1" ? .launchdAgent : .directSpawn
        #else
        return .launchdAgent
        #endif
    }

    func start() {
        guard eventTask == nil else { return }
        eventTask = Task {
            for await event in client.events {
                handle(event)
            }
        }
        ensureConnecting()
    }

    /// "Quit and Stop All Sessions": clean slate — every shell terminated,
    /// the server stopped (a clean exit stays down under launchd too), and
    /// the app quit.
    func closeAllSessionsAndQuit() {
        Task {
            await client.closeAllSessions()
            try? await Task.sleep(for: .milliseconds(200))
            await client.requestServerShutdown()
            try? await Task.sleep(for: .milliseconds(200))
            NSApplication.shared.terminate(nil)
        }
    }

    /// Restarts the server: shells die, the layout persists, and the
    /// connect loop (or launchd) brings a fresh server up immediately.
    func restartServer() {
        Task {
            await client.requestServerRestart()
        }
    }

    // MARK: - Connection loop

    private func ensureConnecting() {
        guard connectTask == nil else { return }
        status = .connecting
        connectTask = Task {
            await connectLoop()
            connectTask = nil
        }
    }

    private func connectLoop() async {
        var delay: Duration = .milliseconds(250)
        // Counts only "a server exists but misbehaves" failures (wedged
        // handshake, ignored restart requests). Absent-server failures
        // (connection refused) must NEVER escalate to a kill: killing
        // nothing helps nothing, and killing a server that is still
        // starting up creates a self-sustaining churn loop.
        var wedgedFailures = 0
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        while !Task.isCancelled {
            do {
                let state = try await client.connect(socketPath: socketPath, appVersion: appVersion)
                status = .connected
                didLaunchServer = false
                onStateChanged?(state)
                onConnected?()
                return
            } catch SessionServerClientError.protocolMismatch {
                Self.logger.warning("Protocol mismatch; requesting server restart")
                requestServerRestartAfterMismatch()
                // Let the next failed connect bring the new binary up again
                // (kickstart under launchd, respawn under direct spawn).
                didLaunchServer = false
                wedgedFailures += 1
            } catch SessionServerClientError.handshakeTimeout {
                Self.logger.error("Handshake timed out; server may be wedged")
                wedgedFailures += 1
            } catch {
                // Typically ECONNREFUSED: no server yet. Bring one up once
                // and give it a moment to bind before the next attempt.
                if !didLaunchServer {
                    didLaunchServer = true
                    bringUpServer()
                    try? await Task.sleep(for: .milliseconds(400))
                }
            }
            // A server that repeatedly accepts but never answers (or
            // ignores restart requests) gets force-killed; the next loop
            // iteration brings up a fresh one.
            if wedgedFailures >= 3, strategy != .external {
                Self.logger.error("Server wedged after \(wedgedFailures) attempts; force-killing")
                forceKillServer()
                didLaunchServer = false
                wedgedFailures = 0
            }
            try? await Task.sleep(for: delay)
            delay = min(delay * 2, .seconds(5))
        }
    }

    /// Last-resort recovery: SIGKILL any running embedded server so a
    /// fresh one can be brought up. Live sessions die (same as a server
    /// crash); layout persists via state.json.
    private func forceKillServer() {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/pkill")
        process.arguments = ["-9", "-f", "Contents/MacOS/sessions-server"]
        try? process.run()
        process.waitUntilExit()
    }

    /// Brings the server up according to the launch strategy. Called once
    /// per connect loop, on the first failed connect attempt.
    private func bringUpServer() {
        switch strategy {
        case .external:
            // A dev server is managed manually; just keep retrying.
            break
        case .directSpawn:
            launchEmbeddedServer()
        case .launchdAgent:
            registerAgent()
        }
    }

    private func handle(_ event: SessionServerEvent) {
        switch event {
        case .stateChanged(let state):
            onStateChanged?(state)
        case .sessionExited(let sessionID, let exitCode):
            onSessionExited?(sessionID, exitCode)
        case .disconnected:
            Self.logger.info("Disconnected from server; reconnecting")
            ensureConnecting()
        case .detachedByOtherClient:
            // Single-window app; another instance took over. Nothing to do
            // in v1 beyond logging.
            Self.logger.warning("A session was attached by another client")
        }
    }

    // MARK: - Server launching (M2: direct spawn; M3 replaces with SMAppService)

    private func launchEmbeddedServer() {
        guard let url = Bundle.main.url(forAuxiliaryExecutable: "sessions-server") else {
            status = .failed("The app bundle has no embedded sessions-server.")
            Self.logger.error("No embedded sessions-server in bundle")
            return
        }
        do {
            let process = Process()
            process.executableURL = url
            try process.run()
            Self.logger.info("Launched embedded sessions-server (pid \(process.processIdentifier))")
        } catch {
            status = .failed("Failed to launch the session server: \(error.localizedDescription)")
            Self.logger.error("Failed to launch sessions-server: \(error)")
        }
    }

    // MARK: - launchd agent (SMAppService)

    private func registerAgent() {
        switch agentService.status {
        case .enabled:
            // Registered, but the socket did not answer: the server was
            // stopped (explicit shutdown) or never started. Kick it.
            kickstartAgent()
        case .requiresApproval:
            status = .needsApproval
            startApprovalPolling()
        case .notRegistered, .notFound:
            do {
                try agentService.register()
                Self.logger.info("Registered launchd agent")
                kickstartAgent()
            } catch {
                if agentService.status == .requiresApproval {
                    status = .needsApproval
                    startApprovalPolling()
                } else {
                    status = .failed("Could not register the session server: \(error.localizedDescription)")
                    Self.logger.error("Agent registration failed: \(error)")
                }
            }
        @unknown default:
            status = .failed("Unknown launchd agent status")
        }
    }

    /// Opens System Settings > Login Items so the user can approve the agent.
    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    /// Re-registers the agent (engineering mode; fixes stale registrations).
    func reregisterAgent() {
        try? agentService.unregister()
        didLaunchServer = false
        ensureConnecting()
    }

    private func startApprovalPolling() {
        Task {
            while agentService.status == .requiresApproval {
                try? await Task.sleep(for: .seconds(2))
            }
            if agentService.status == .enabled {
                Self.logger.info("Agent approved by user")
                status = .connecting
                kickstartAgent()
            }
        }
    }

    /// `RunAtLoad` only fires at registration/login, and `KeepAlive` with
    /// `SuccessfulExit = false` does not revive a cleanly stopped server,
    /// so nudge launchd explicitly.
    private func kickstartAgent() {
        let process = Process()
        process.executableURL = URL(filePath: "/bin/launchctl")
        process.arguments = ["kickstart", "gui/\(getuid())/\(Self.agentLabel)"]
        try? process.run()
    }

    /// After an app update the running server may speak an old protocol.
    /// Connect on a throwaway socket just to ask it to exit; launchd (M3)
    /// or the connect loop (M2) then brings up the new binary.
    private func requestServerRestartAfterMismatch() {
        Task.detached { [socketPath] in
            guard let connection = try? UnixSocketConnection.connect(to: socketPath) else {
                return
            }
            connection.send(.control(.restartServer))
            try? await Task.sleep(for: .milliseconds(200))
            connection.close()
        }
    }
}
