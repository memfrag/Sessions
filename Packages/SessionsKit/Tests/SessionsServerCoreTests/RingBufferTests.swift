//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import Testing
@testable import SessionsServerCore

struct RingBufferTests {

    @Test func appendBelowCapacity() {
        var ring = RingBuffer(capacity: 10)
        ring.append([1, 2, 3])
        #expect(ring.snapshot() == [1, 2, 3])
        ring.append([4, 5])
        #expect(ring.snapshot() == [1, 2, 3, 4, 5])
    }

    @Test func wrapsAndKeepsNewest() {
        var ring = RingBuffer(capacity: 5)
        ring.append([1, 2, 3, 4])
        ring.append([5, 6, 7])
        #expect(ring.snapshot() == [3, 4, 5, 6, 7])
        #expect(ring.count == 5)
    }

    @Test func appendLargerThanCapacity() {
        var ring = RingBuffer(capacity: 4)
        ring.append([1, 2, 3, 4, 5, 6, 7, 8, 9])
        #expect(ring.snapshot() == [6, 7, 8, 9])
    }

    @Test func manySmallAppendsPreserveOrder() {
        var ring = RingBuffer(capacity: 16)
        for value in 0..<100 {
            ring.append([UInt8(value % 256)])
        }
        let expected = (84..<100).map { UInt8($0 % 256) }
        #expect(ring.snapshot() == expected)
    }

    @Test func clearEmptiesBuffer() {
        var ring = RingBuffer(capacity: 8)
        ring.append([1, 2, 3])
        ring.clear()
        #expect(ring.snapshot().isEmpty)
        ring.append([9])
        #expect(ring.snapshot() == [9])
    }
}
