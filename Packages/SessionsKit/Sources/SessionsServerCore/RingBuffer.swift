//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

/// Fixed-capacity circular byte buffer holding the most recent PTY output,
/// replayed to clients on attach.
struct RingBuffer: Sendable {

    private var storage: [UInt8]

    private var head = 0

    private(set) var count = 0

    let capacity: Int

    init(capacity: Int) {
        self.capacity = capacity
        storage = [UInt8](repeating: 0, count: capacity)
    }

    mutating func append(_ bytes: [UInt8]) {
        guard capacity > 0 else { return }
        // Only the last `capacity` bytes matter.
        let relevant = bytes.count > capacity ? Array(bytes.suffix(capacity)) : bytes
        for byte in relevant {
            storage[(head + count) % capacity] = byte
            if count < capacity {
                count += 1
            } else {
                head = (head + 1) % capacity
            }
        }
    }

    /// The buffered bytes, oldest first.
    func snapshot() -> [UInt8] {
        var result = [UInt8]()
        result.reserveCapacity(count)
        for index in 0..<count {
            result.append(storage[(head + index) % capacity])
        }
        return result
    }

    mutating func clear() {
        head = 0
        count = 0
    }
}
