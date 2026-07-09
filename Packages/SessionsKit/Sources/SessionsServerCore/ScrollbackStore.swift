//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import Foundation
import OSLog

/// Persists per-session scrollback buffers across graceful server exits
/// (restart, shutdown, SIGTERM at reboot) as raw byte files next to the
/// state file. Crashes lose the buffers — accepted; the layout itself is
/// persisted on every change by `StateStore`.
///
/// Everything is best-effort: a missing or torn file just means lost
/// scrollback, never a failed boot.
struct ScrollbackStore {

    private static let logger = Logger(subsystem: "io.apparata.Sessions", category: "ScrollbackStore")

    /// Directory holding one `<sessionID>.bin` per session.
    let directory: String

    /// - Parameter statePath: the state.json path; scrollback lives in a
    ///   `scrollback` directory beside it.
    init(statePath: String) {
        directory = (statePath as NSString).deletingLastPathComponent + "/scrollback"
    }

    private func filePath(for sessionID: UUID) -> String {
        directory + "/\(sessionID.uuidString).bin"
    }

    func load(sessionID: UUID) -> [UInt8]? {
        guard let data = FileManager.default.contents(atPath: filePath(for: sessionID)),
              !data.isEmpty else {
            return nil
        }
        return [UInt8](data)
    }

    func save(sessionID: UUID, bytes: [UInt8]) {
        guard !bytes.isEmpty else {
            delete(sessionID: sessionID)
            return
        }
        do {
            try FileManager.default.createDirectory(
                atPath: directory,
                withIntermediateDirectories: true
            )
            try Data(bytes).write(to: URL(filePath: filePath(for: sessionID)), options: .atomic)
        } catch {
            Self.logger.error("Failed to save scrollback for \(sessionID): \(error)")
        }
    }

    func delete(sessionID: UUID) {
        try? FileManager.default.removeItem(atPath: filePath(for: sessionID))
    }

    /// Boot-time GC: removes files for sessions that no longer exist in
    /// the persisted layout.
    func deleteAll(notIn keep: Set<UUID>) {
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: directory) else {
            return
        }
        for file in files where file.hasSuffix(".bin") {
            let name = (file as NSString).deletingPathExtension
            if let id = UUID(uuidString: name), keep.contains(id) {
                continue
            }
            try? FileManager.default.removeItem(atPath: directory + "/\(file)")
        }
    }
}
