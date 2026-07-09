//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import Foundation
import MachO

/// Identifies exact builds via the Mach-O LC_UUID, which the linker
/// regenerates on every build. Version strings can't tell two dev builds
/// apart; the build UUID can — it's how the app detects that the running
/// server predates the binary embedded in the current bundle.
public enum BuildID {

    /// LC_UUID of the running executable, read from the loaded image in
    /// memory — deliberately NOT from its file on disk, which may have
    /// been replaced by a rebuild or update since launch.
    public static func current() -> String? {
        for index in 0..<_dyld_image_count() {
            guard let header = _dyld_get_image_header(index),
                  header.pointee.magic == MH_MAGIC_64,
                  header.pointee.filetype == MH_EXECUTE else {
                continue
            }
            return uuidOfLoadedImage(header: UnsafeRawPointer(header))
        }
        return nil
    }

    /// Walks the load commands of a loaded 64-bit image for LC_UUID.
    private static func uuidOfLoadedImage(header: UnsafeRawPointer) -> String? {
        let commandCount = header.loadUnaligned(fromByteOffset: 16, as: UInt32.self)
        var cursor = header + MemoryLayout<mach_header_64>.size
        for _ in 0..<commandCount {
            let command = cursor.loadUnaligned(as: UInt32.self)
            let commandSize = Int(cursor.loadUnaligned(fromByteOffset: 4, as: UInt32.self))
            if command == UInt32(LC_UUID) {
                let uuidCommand = cursor.loadUnaligned(as: uuid_command.self)
                return UUID(uuid: uuidCommand.uuid).uuidString
            }
            guard commandSize >= 8 else { return nil }
            cursor += commandSize
        }
        return nil
    }

    /// LC_UUID of a Mach-O binary on disk (thin 64-bit or fat).
    public static func ofBinary(atPath path: String) -> String? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return uuid(in: data)
    }

    private static func uuid(in data: Data) -> String? {
        guard data.count >= 8 else { return nil }
        let magic = loadUInt32(data, at: 0)
        // Fat binary: big-endian header. The slices have DIFFERENT UUIDs,
        // so pick the one matching the running architecture (that is the
        // slice the kernel would execute), falling back to any slice.
        if magic == FAT_MAGIC.bigEndian || magic == FAT_MAGIC {
            let archCount = Int(UInt32(bigEndian: loadUInt32(data, at: 4)))
            let hostType = hostCPUType()
            var fallback: String?
            for index in 0..<archCount {
                let base = 8 + index * 20
                guard data.count >= base + 20 else { return fallback }
                let cpuType = Int32(bitPattern: UInt32(bigEndian: loadUInt32(data, at: base)))
                let offset = Int(UInt32(bigEndian: loadUInt32(data, at: base + 8)))
                let size = Int(UInt32(bigEndian: loadUInt32(data, at: base + 12)))
                guard offset > 0, size > 0, data.count >= offset + size else { continue }
                guard let found = uuid(in: data.subdata(in: offset..<(offset + size))) else { continue }
                if cpuType == hostType {
                    return found
                }
                fallback = fallback ?? found
            }
            return fallback
        }
        guard magic == MH_MAGIC_64 else { return nil }
        // Walk the load commands after the 64-bit header for LC_UUID.
        let headerSize = MemoryLayout<mach_header_64>.size
        guard data.count >= headerSize else { return nil }
        let commandCount = loadUInt32(data, at: 16)
        var offset = headerSize
        for _ in 0..<commandCount {
            guard data.count >= offset + 8 else { return nil }
            let command = loadUInt32(data, at: offset)
            let commandSize = Int(loadUInt32(data, at: offset + 4))
            if command == UInt32(LC_UUID), data.count >= offset + 24 {
                var uuid = uuid_t(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
                withUnsafeMutableBytes(of: &uuid) { destination in
                    data.withUnsafeBytes { source in
                        destination.copyMemory(
                            from: UnsafeRawBufferPointer(rebasing: source[(offset + 8)..<(offset + 24)])
                        )
                    }
                }
                return UUID(uuid: uuid).uuidString
            }
            guard commandSize >= 8 else { return nil }
            offset += commandSize
        }
        return nil
    }

    private static func loadUInt32(_ data: Data, at offset: Int) -> UInt32 {
        data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) }
    }

    /// CPU type of the running executable image.
    private static func hostCPUType() -> cpu_type_t? {
        for index in 0..<_dyld_image_count() {
            guard let header = _dyld_get_image_header(index),
                  header.pointee.filetype == MH_EXECUTE else {
                continue
            }
            return header.pointee.cputype
        }
        return nil
    }
}
