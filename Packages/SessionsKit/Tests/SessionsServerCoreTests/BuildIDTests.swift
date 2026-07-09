//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import Foundation
import Testing
@testable import SessionsIPC

struct BuildIDTests {

    /// The in-memory reader and the on-disk parser must agree when the
    /// binary has not been replaced — here, the test runner itself.
    /// (Bundle.main is NOT the main executable under swift test, so the
    /// path comes from _NSGetExecutablePath.)
    @Test func currentMatchesOwnBinaryOnDisk() throws {
        let current = try #require(BuildID.current())
        var size = UInt32(4096)
        var buffer = [CChar](repeating: 0, count: Int(size))
        #expect(_NSGetExecutablePath(&buffer, &size) == 0)
        let executablePath = String(cString: buffer)
        let onDisk = try #require(BuildID.ofBinary(atPath: executablePath))
        #expect(current == onDisk)
    }

    @Test func missingFileReturnsNil() {
        #expect(BuildID.ofBinary(atPath: "/nonexistent/binary") == nil)
    }

    @Test func nonMachOFileReturnsNil() throws {
        let path = "/tmp/buildid-test-\(UUID().uuidString).txt"
        defer { try? FileManager.default.removeItem(atPath: path) }
        try Data("not a mach-o binary".utf8).write(to: URL(filePath: path))
        #expect(BuildID.ofBinary(atPath: path) == nil)
    }
}
