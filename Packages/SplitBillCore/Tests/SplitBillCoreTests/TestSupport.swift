import Foundation
@testable import SplitBillCore

/// Deterministic RNG (splitmix64) for property-style tests.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

enum Fixtures {
    static func host(_ name: String = "Hano") -> Member {
        Member(displayName: name, avatarEmoji: "👑", isHost: true)
    }

    static func member(_ name: String, emoji: String = "🙂") -> Member {
        Member(displayName: name, avatarEmoji: emoji)
    }

    /// Room in `.open` with a host and the given extra members already joined.
    static func openRoom(host: Member, members: [Member] = []) throws -> Room {
        var room = Room(name: "Dinner", host: host)
        for member in members {
            try room.join(member)
        }
        return room
    }

    /// Room in `.claiming` with one bill added while `.open`.
    static func claimingRoom(
        host: Member,
        members: [Member],
        bill: Bill
    ) throws -> Room {
        var room = try openRoom(host: host, members: members)
        try room.addBill(bill, by: host.id)
        try room.advance(by: host.id)
        return room
    }
}
