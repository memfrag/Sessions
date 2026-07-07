//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import Darwin
import Foundation

enum PtyProcessError: Error {
    case forkFailed
    case allocationFailed
}

/// A child process running under a pseudo-terminal.
///
/// Thin wrapper around `forkpty` modeled on SwiftTerm's
/// `PseudoTerminalHelpers`. Confined to the owning `SessionActor`.
final class PtyProcess {

    let pid: pid_t

    let masterFd: Int32

    /// The child is the session leader of its own process group, so its
    /// process group ID equals its pid.
    var shellProcessGroupID: pid_t { pid }

    init(
        executable: String,
        args: [String],
        environment: [String],
        currentDirectory: String,
        cols: Int,
        rows: Int
    ) throws {
        var windowSize = winsize(
            ws_row: UInt16(rows),
            ws_col: UInt16(cols),
            ws_xpixel: 0,
            ws_ypixel: 0
        )
        // argv[0] first, then the arguments.
        guard let argv = Self.allocateCStringArray(args),
              let envp = Self.allocateCStringArray(environment),
              let cExecutable = strdup(executable),
              let cDirectory = strdup(currentDirectory) else {
            throw PtyProcessError.allocationFailed
        }
        defer {
            Self.freeCStringArray(argv)
            Self.freeCStringArray(envp)
            free(cExecutable)
            free(cDirectory)
        }
        var master: Int32 = 0
        let forkResult = forkpty(&master, nil, nil, &windowSize)
        if forkResult < 0 {
            throw PtyProcessError.forkFailed
        }
        if forkResult == 0 {
            // Child: only async-signal-safe calls until execve.
            _ = chdir(cDirectory)
            _ = execve(cExecutable, argv.base, envp.base)
            _exit(127)
        }
        pid = forkResult
        masterFd = master
        SocketHelpers.setNonBlocking(master)
        SocketHelpers.setCloseOnExec(master)
    }

    func resize(cols: Int, rows: Int) {
        var windowSize = winsize(
            ws_row: UInt16(rows),
            ws_col: UInt16(cols),
            ws_xpixel: 0,
            ws_ypixel: 0
        )
        _ = ioctl(masterFd, TIOCSWINSZ, &windowSize)
    }

    /// Process group currently in the foreground on the terminal.
    func foregroundProcessGroupID() -> pid_t? {
        let pgid = tcgetpgrp(masterFd)
        return pgid > 0 ? pgid : nil
    }

    /// Whether something other than the shell itself is in the foreground.
    func isBusy() -> Bool {
        guard let foreground = foregroundProcessGroupID() else { return false }
        return foreground != shellProcessGroupID
    }

    /// Current working directory of the foreground process (the group
    /// leader), via `proc_pidinfo`. Used for cwd inheritance in new tabs.
    func foregroundWorkingDirectory() -> String? {
        let targetPid = foregroundProcessGroupID() ?? pid
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        let result = proc_pidinfo(targetPid, PROC_PIDVNODEPATHINFO, 0, &info, size)
        guard result == size else {
            return nil
        }
        return withUnsafeBytes(of: &info.pvi_cdir.vip_path) { pointer in
            guard let base = pointer.baseAddress else { return nil }
            return String(cString: base.assumingMemoryBound(to: CChar.self))
        }
    }

    /// Politely asks the process group to die (SIGHUP), like closing a
    /// real terminal would.
    func hangUp() {
        killpg(shellProcessGroupID, SIGHUP)
    }

    /// Force-kills the process group.
    func forceKill() {
        killpg(shellProcessGroupID, SIGKILL)
    }

    func closeMaster() {
        close(masterFd)
    }

    // MARK: - C string arrays

    private struct CStringArray {
        let base: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>
        let count: Int
    }

    private static func allocateCStringArray(_ strings: [String]) -> CStringArray? {
        let base = UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>.allocate(capacity: strings.count + 1)
        var initialized = 0
        for (index, string) in strings.enumerated() {
            guard let duplicated = strdup(string) else {
                for cleanupIndex in 0..<initialized {
                    free(base[cleanupIndex])
                }
                base.deallocate()
                return nil
            }
            base[index] = duplicated
            initialized += 1
        }
        base[strings.count] = nil
        return CStringArray(base: base, count: strings.count)
    }

    private static func freeCStringArray(_ array: CStringArray) {
        for index in 0..<array.count {
            free(array.base[index])
        }
        array.base.deallocate()
    }
}

enum SocketHelpers {

    static func setNonBlocking(_ fd: Int32) {
        let flags = fcntl(fd, F_GETFL, 0)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
    }

    static func setCloseOnExec(_ fd: Int32) {
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
    }
}
