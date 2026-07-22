import CloudKit
import Foundation
import Testing
import SplitBillCore
@testable import SplitBillSync

/// Hermetic mapping tests: CKRecords are plain data containers offline —
/// no CloudKit account, container, or network is touched.
@Suite("RecordMapper round trips")
struct RecordMapperTests {

    private let zoneID = CKRecordZone.ID(zoneName: "room-test", ownerName: CKCurrentUserDefaultName)

    /// A room exercising every enum case and claim shape.
    private func fixtureRoom() -> Room {
        let host = Member(displayName: "Hano", avatarEmoji: "🧑‍🍳", isHost: true)
        let dita = Member(displayName: "Dita", avatarEmoji: "🐱", paymentStatus: .memberMarkedPaid)
        let raka = Member(displayName: "Raka", avatarEmoji: "🦖", paymentStatus: .hostConfirmed)

        var room = Room(name: "Makan Malam", host: host)
        try! room.join(dita)
        try! room.join(raka)
        // join() resets paymentStatus — rebuild via rehydration for fidelity.
        let members = [
            host,
            Member(id: dita.id, displayName: dita.displayName, avatarEmoji: dita.avatarEmoji,
                   isHost: false, paymentStatus: .memberMarkedPaid),
            Member(id: raka.id, displayName: raka.displayName, avatarEmoji: raka.avatarEmoji,
                   isHost: false, paymentStatus: .hostConfirmed),
        ]

        let soloID = UUID()
        let sharedID = UUID()
        let assignedID = UUID()
        let bill = Bill(
            merchantName: "Warung Tekko",
            photoReference: "photo-123",
            tax: 14_175,
            serviceCharge: 6_750,
            discount: 5_000,
            items: [
                BillItem(id: soloID, name: "Nasi Goreng", unitPrice: 55_000,
                         claimState: .claimed([Claim(itemID: soloID, memberID: dita.id, portion: .one)])),
                BillItem(id: sharedID, name: "Kentang", unitPrice: 25_000,
                         claimState: .claimed([
                             Claim(itemID: sharedID, memberID: host.id, portion: Fraction(1, 3)),
                             Claim(itemID: sharedID, memberID: dita.id, portion: Fraction(1, 3)),
                             Claim(itemID: sharedID, memberID: raka.id, portion: Fraction(1, 3)),
                         ])),
                BillItem(id: assignedID, name: "Gurame", unitPrice: 85_000,
                         claimState: .forceAssigned(raka.id)),
                BillItem(name: "Es Teh", unitPrice: 10_000), // unclaimed
            ],
            createdAt: Date(timeIntervalSince1970: 1_770_000_000)
        )
        let secondBill = Bill(
            merchantName: "Kopi Kenangan",
            tax: 1_980,
            serviceCharge: 0,
            discount: 0,
            items: [BillItem(name: "Americano", unitPrice: 18_000)],
            createdAt: Date(timeIntervalSince1970: 1_770_000_100)
        )

        return Room(
            rehydrating: room.id,
            name: room.name,
            state: .claiming,
            hostMemberID: host.id,
            createdAt: Date(timeIntervalSince1970: 1_769_999_000),
            members: members,
            bills: [bill, secondBill]
        )
    }

    @Test("Full room graph survives record round trip exactly")
    func fullRoomRoundTrip() throws {
        let original = fixtureRoom()
        let records = RecordMapper.records(for: original, zoneID: zoneID)
        // 1 room + 3 members + 2 bills + 5 items.
        #expect(records.count == 11)

        let decoded = try RecordMapper.room(from: records.shuffled())
        #expect(decoded == original)
    }

    @Test("Round trip preserves every enum case and claim shape")
    func enumAndClaimFidelity() throws {
        let original = fixtureRoom()
        let decoded = try RecordMapper.room(
            from: RecordMapper.records(for: original, zoneID: zoneID)
        )

        #expect(decoded.state == .claiming)
        #expect(decoded.members.map(\.paymentStatus) == [.none, .memberMarkedPaid, .hostConfirmed])
        #expect(decoded.bills[0].tax == 14_175)
        #expect(decoded.bills[0].serviceCharge == 6_750)
        #expect(decoded.bills[0].discount == 5_000)
        #expect(decoded.bills[1].tax == 1_980)

        let items = decoded.bills[0].items
        #expect(items[0].claimState.claimerIDs.count == 1)
        if case .claimed(let claims) = items[1].claimState {
            #expect(claims.map(\.portion) == [Fraction(1, 3), Fraction(1, 3), Fraction(1, 3)])
            #expect(claims.allSatisfy { $0.itemID == items[1].id })
        } else {
            Issue.record("Expected shared claim")
        }
        if case .forceAssigned = items[2].claimState {} else {
            Issue.record("Expected force-assigned")
        }
        #expect(items[3].claimState == .unclaimed)
    }

    @Test("Money stays exact Int rupiah through the trip")
    func moneyFidelity() throws {
        let decoded = try RecordMapper.room(
            from: RecordMapper.records(for: fixtureRoom(), zoneID: zoneID)
        )
        #expect(decoded.bills[0].items.map(\.unitPrice) == [55_000, 25_000, 85_000, 10_000])
        #expect(decoded.bills[0].subtotal == 175_000)
    }

    @Test("Claim-state rewrite on an existing record (conflict repair path)")
    func claimStateRewrite() throws {
        let itemID = UUID()
        let member = UUID()
        let record = RecordMapper.itemRecord(
            for: BillItem(id: itemID, name: "Sate", unitPrice: 35_000),
            sortIndex: 0,
            billRef: CKRecord.Reference(
                recordID: CKRecord.ID(recordName: UUID().uuidString, zoneID: zoneID),
                action: .none
            ),
            zoneID: zoneID
        )
        #expect(try RecordMapper.claimState(from: record) == .unclaimed)

        RecordMapper.applyClaimState(
            .claimed([Claim(itemID: itemID, memberID: member, portion: .one)]),
            to: record
        )
        #expect(try RecordMapper.claimState(from: record)
            == .claimed([Claim(itemID: itemID, memberID: member, portion: .one)]))

        RecordMapper.applyClaimState(.forceAssigned(member), to: record)
        #expect(try RecordMapper.claimState(from: record) == .forceAssigned(member))

        RecordMapper.applyClaimState(.unclaimed, to: record)
        #expect(try RecordMapper.claimState(from: record) == .unclaimed)
    }

    @Test("Corrupt records throw typed mapping errors instead of crashing")
    func corruptRecords() throws {
        #expect(throws: RecordMappingError.missingRoomRecord) {
            _ = try RecordMapper.room(from: [])
        }

        let bad = CKRecord(
            recordType: RecordSchema.ItemType.name,
            recordID: CKRecord.ID(recordName: UUID().uuidString, zoneID: zoneID)
        )
        bad[RecordSchema.ItemType.itemName] = "Sate"
        bad[RecordSchema.ItemType.unitPrice] = 35_000
        bad[RecordSchema.ItemType.claimKind] = "claimed"
        bad[RecordSchema.ItemType.claimMemberIDs] = [UUID().uuidString]
        bad[RecordSchema.ItemType.claimNumerators] = [1, 2] // length mismatch
        bad[RecordSchema.ItemType.claimDenominators] = [2]
        #expect(throws: RecordMappingError.self) {
            _ = try RecordMapper.item(from: bad)
        }
    }

    @Test("Zone names embed and recover the room ID")
    func zoneNames() {
        let id = UUID()
        #expect(RecordSchema.roomID(fromZoneName: RecordSchema.zoneName(roomID: id)) == id)
        #expect(RecordSchema.roomID(fromZoneName: "other-zone") == nil)
    }
}
