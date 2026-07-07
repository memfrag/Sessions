//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import Dispatch
import Foundation
import OSLog
import SessionsIPC
import SessionsProtocol
import SessionsServerCore

let logger = Logger(subsystem: "io.apparata.Sessions", category: "sessions-server")

// Detach from the launching process's session/group so that killing the app
// (Xcode stop, crash, force quit) never takes the server down with it.
// Fails harmlessly with EPERM when already a session leader (launchd case).
_ = setsid()

// Minimal argument parsing: --socket <path> and --state <path> overrides.
var socketPath = SessionsServerPaths.resolvedSocketPath()
var statePath = SessionsServerPaths.defaultStatePath()
var arguments = CommandLine.arguments.dropFirst().makeIterator()
while let argument = arguments.next() {
    switch argument {
    case "--socket":
        if let value = arguments.next() {
            socketPath = value
        }
    case "--state":
        if let value = arguments.next() {
            statePath = value
        }
    default:
        FileHandle.standardError.write(Data("Unknown argument: \(argument)\n".utf8))
        exit(64)
    }
}

let serverVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"

let core: ServerCore
do {
    core = try ServerCore(socketPath: socketPath, statePath: statePath, serverVersion: serverVersion)
} catch UnixSocketError.alreadyRunning(let path) {
    logger.error("Another server is already running on \(path)")
    exit(0)
} catch {
    logger.error("Failed to start server: \(error)")
    exit(1)
}

// Graceful shutdown on SIGTERM (launchd) and SIGINT (Ctrl-C in dev).
signal(SIGTERM, SIG_IGN)
signal(SIGINT, SIG_IGN)
let termSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
termSource.setEventHandler {
    Task {
        await core.persistAndExit(code: 0)
    }
}
termSource.activate()
let intSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
intSource.setEventHandler {
    Task {
        await core.persistAndExit(code: 0)
    }
}
intSource.activate()

logger.info("sessions-server \(serverVersion) listening on \(socketPath)")
await core.run()
