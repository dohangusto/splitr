import CloudKit
import Foundation
import SplitBillCore

public enum RecordMappingError: Error, Equatable {
    case missingField(recordType: String, field: String)
    case invalidValue(recordType: String, field: String)
    case invalidRecordName(String)
    case missingRoomRecord
    case claimArrayMismatch(itemID: UUID)
}

/// Pure, bidirectional mapping between the Core domain graph and CKRecords.
/// No CloudKit I/O happens here — records are plain data containers, so
/// every function is unit-testable offline.
///
/// Record names are the domain UUIDs, so identity survives the round trip.
/// Array order (members, bills, items) is preserved via `sortIndex`.
public enum RecordMapper {

    // MARK: - Domain → records

    /// The full record graph for a room, in parent-first save order.
    public static func records(for room: Room, zoneID: CKRecordZone.ID) -> [CKRecord] {
        var records = [roomRecord(for: room, zoneID: zoneID)]
        let roomRef = CKRecord.Reference(
            recordID: recordID(room.id, zoneID: zoneID),
            action: .none
        )
        for (index, member) in room.members.enumerated() {
            records.append(memberRecord(for: member, sortIndex: index, roomRef: roomRef, zoneID: zoneID))
        }
        for (index, bill) in room.bills.enumerated() {
            records.append(billRecord(for: bill, sortIndex: index, roomRef: roomRef, zoneID: zoneID))
            let billRef = CKRecord.Reference(
                recordID: recordID(bill.id, zoneID: zoneID),
                action: .none
            )
            for (itemIndex, item) in bill.items.enumerated() {
                records.append(itemRecord(for: item, sortIndex: itemIndex, billRef: billRef, zoneID: zoneID))
            }
        }
        return records
    }

    public static func roomRecord(for room: Room, zoneID: CKRecordZone.ID) -> CKRecord {
        let record = CKRecord(
            recordType: RecordSchema.RoomType.name,
            recordID: recordID(room.id, zoneID: zoneID)
        )
        applyRoomFields(room, to: record)
        return record
    }

    /// Copies room fields onto an existing record (preserves the server
    /// change tag when updating a fetched record).
    public static func applyRoomFields(_ room: Room, to record: CKRecord) {
        record[RecordSchema.RoomType.roomName] = room.name
        record[RecordSchema.RoomType.state] = room.state.rawValue
        record[RecordSchema.RoomType.hostMemberID] = room.hostMemberID.uuidString
        record[RecordSchema.RoomType.createdAt] = room.createdAt
    }

    public static func memberRecord(
        for member: Member,
        sortIndex: Int,
        roomRef: CKRecord.Reference,
        zoneID: CKRecordZone.ID
    ) -> CKRecord {
        let record = CKRecord(
            recordType: RecordSchema.MemberType.name,
            recordID: recordID(member.id, zoneID: zoneID)
        )
        applyMemberFields(member, sortIndex: sortIndex, roomRef: roomRef, to: record)
        return record
    }

    public static func applyMemberFields(
        _ member: Member,
        sortIndex: Int,
        roomRef: CKRecord.Reference,
        to record: CKRecord
    ) {
        record[RecordSchema.MemberType.displayName] = member.displayName
        record[RecordSchema.MemberType.avatarEmoji] = member.avatarEmoji
        record[RecordSchema.MemberType.isHost] = member.isHost ? 1 : 0
        record[RecordSchema.MemberType.paymentStatus] = member.paymentStatus.rawValue
        record[RecordSchema.MemberType.sortIndex] = sortIndex
        record[RecordSchema.MemberType.roomRef] = roomRef
    }

    public static func billRecord(
        for bill: Bill,
        sortIndex: Int,
        roomRef: CKRecord.Reference,
        zoneID: CKRecordZone.ID
    ) -> CKRecord {
        let record = CKRecord(
            recordType: RecordSchema.BillType.name,
            recordID: recordID(bill.id, zoneID: zoneID)
        )
        record[RecordSchema.BillType.merchantName] = bill.merchantName
        record[RecordSchema.BillType.photoReference] = bill.photoReference
        record[RecordSchema.BillType.taxRateBasisPoints] = bill.taxRate.basisPoints
        record[RecordSchema.BillType.serviceRateBasisPoints] = bill.serviceChargeRate.basisPoints
        record[RecordSchema.BillType.taxBasis] = bill.taxBasis.rawValue
        record[RecordSchema.BillType.createdAt] = bill.createdAt
        record[RecordSchema.BillType.sortIndex] = sortIndex
        record[RecordSchema.BillType.roomRef] = roomRef
        return record
    }

    public static func itemRecord(
        for item: BillItem,
        sortIndex: Int,
        billRef: CKRecord.Reference,
        zoneID: CKRecordZone.ID
    ) -> CKRecord {
        let record = CKRecord(
            recordType: RecordSchema.ItemType.name,
            recordID: recordID(item.id, zoneID: zoneID)
        )
        record[RecordSchema.ItemType.itemName] = item.name
        record[RecordSchema.ItemType.unitPrice] = item.unitPrice
        record[RecordSchema.ItemType.sortIndex] = sortIndex
        record[RecordSchema.ItemType.billRef] = billRef
        applyClaimState(item.claimState, to: record)
        return record
    }

    /// Claim state is the contended field in claim races, so it gets its own
    /// apply function — conflict resolution rewrites just these keys on the
    /// authoritative server record.
    public static func applyClaimState(_ state: ClaimState, to record: CKRecord) {
        switch state {
        case .unclaimed:
            record[RecordSchema.ItemType.claimKind] = RecordSchema.ClaimKind.unclaimed
            record[RecordSchema.ItemType.claimMemberIDs] = nil
            record[RecordSchema.ItemType.claimNumerators] = nil
            record[RecordSchema.ItemType.claimDenominators] = nil
        case .claimed(let claims):
            record[RecordSchema.ItemType.claimKind] = RecordSchema.ClaimKind.claimed
            record[RecordSchema.ItemType.claimMemberIDs] = claims.map(\.memberID.uuidString)
            record[RecordSchema.ItemType.claimNumerators] = claims.map(\.portion.numerator)
            record[RecordSchema.ItemType.claimDenominators] = claims.map(\.portion.denominator)
        case .forceAssigned(let memberID):
            record[RecordSchema.ItemType.claimKind] = RecordSchema.ClaimKind.forceAssigned
            record[RecordSchema.ItemType.claimMemberIDs] = [memberID.uuidString]
            record[RecordSchema.ItemType.claimNumerators] = nil
            record[RecordSchema.ItemType.claimDenominators] = nil
        }
    }

    public static func recordID(_ id: UUID, zoneID: CKRecordZone.ID) -> CKRecord.ID {
        CKRecord.ID(recordName: id.uuidString, zoneID: zoneID)
    }

    // MARK: - Records → domain

    /// Assembles a Room from the records of one zone (any order).
    public static func room(from records: [CKRecord]) throws -> Room {
        guard let roomRecord = records.first(where: { $0.recordType == RecordSchema.RoomType.name }) else {
            throw RecordMappingError.missingRoomRecord
        }
        let roomID = try uuid(fromRecordName: roomRecord.recordID.recordName)

        let members = try records
            .filter { $0.recordType == RecordSchema.MemberType.name }
            .sorted { intValue($0, RecordSchema.MemberType.sortIndex) < intValue($1, RecordSchema.MemberType.sortIndex) }
            .map(member(from:))

        var bills = try records
            .filter { $0.recordType == RecordSchema.BillType.name }
            .sorted { intValue($0, RecordSchema.BillType.sortIndex) < intValue($1, RecordSchema.BillType.sortIndex) }
            .map(bill(from:))

        let itemRecords = records.filter { $0.recordType == RecordSchema.ItemType.name }
        for index in bills.indices {
            bills[index].items = try itemRecords
                .filter {
                    ($0[RecordSchema.ItemType.billRef] as? CKRecord.Reference)?
                        .recordID.recordName == bills[index].id.uuidString
                }
                .sorted { intValue($0, RecordSchema.ItemType.sortIndex) < intValue($1, RecordSchema.ItemType.sortIndex) }
                .map(item(from:))
        }

        return Room(
            rehydrating: roomID,
            name: try string(roomRecord, RecordSchema.RoomType.roomName),
            state: try rawValue(RoomState.self, roomRecord, RecordSchema.RoomType.state),
            hostMemberID: try uuidField(roomRecord, RecordSchema.RoomType.hostMemberID),
            createdAt: try date(roomRecord, RecordSchema.RoomType.createdAt),
            members: members,
            bills: bills
        )
    }

    public static func member(from record: CKRecord) throws -> Member {
        Member(
            id: try uuid(fromRecordName: record.recordID.recordName),
            displayName: try string(record, RecordSchema.MemberType.displayName),
            avatarEmoji: try string(record, RecordSchema.MemberType.avatarEmoji),
            isHost: intValue(record, RecordSchema.MemberType.isHost) == 1,
            paymentStatus: try rawValue(PaymentStatus.self, record, RecordSchema.MemberType.paymentStatus)
        )
    }

    public static func bill(from record: CKRecord) throws -> Bill {
        Bill(
            id: try uuid(fromRecordName: record.recordID.recordName),
            merchantName: try string(record, RecordSchema.BillType.merchantName),
            photoReference: record[RecordSchema.BillType.photoReference] as? String,
            taxRate: Rate(basisPoints: intValue(record, RecordSchema.BillType.taxRateBasisPoints)),
            serviceChargeRate: Rate(basisPoints: intValue(record, RecordSchema.BillType.serviceRateBasisPoints)),
            taxBasis: try rawValue(TaxBasis.self, record, RecordSchema.BillType.taxBasis),
            items: [],
            createdAt: try date(record, RecordSchema.BillType.createdAt)
        )
    }

    public static func item(from record: CKRecord) throws -> BillItem {
        BillItem(
            id: try uuid(fromRecordName: record.recordID.recordName),
            name: try string(record, RecordSchema.ItemType.itemName),
            unitPrice: intValue(record, RecordSchema.ItemType.unitPrice),
            claimState: try claimState(from: record)
        )
    }

    public static func claimState(from record: CKRecord) throws -> ClaimState {
        let itemID = try uuid(fromRecordName: record.recordID.recordName)
        let kind = try string(record, RecordSchema.ItemType.claimKind)
        let memberIDs = try (record[RecordSchema.ItemType.claimMemberIDs] as? [String] ?? [])
            .map { raw -> UUID in
                guard let id = UUID(uuidString: raw) else {
                    throw RecordMappingError.invalidValue(
                        recordType: record.recordType,
                        field: RecordSchema.ItemType.claimMemberIDs
                    )
                }
                return id
            }

        switch kind {
        case RecordSchema.ClaimKind.unclaimed:
            return .unclaimed
        case RecordSchema.ClaimKind.forceAssigned:
            guard let assignee = memberIDs.first else {
                throw RecordMappingError.missingField(
                    recordType: record.recordType,
                    field: RecordSchema.ItemType.claimMemberIDs
                )
            }
            return .forceAssigned(assignee)
        case RecordSchema.ClaimKind.claimed:
            let numerators = record[RecordSchema.ItemType.claimNumerators] as? [Int] ?? []
            let denominators = record[RecordSchema.ItemType.claimDenominators] as? [Int] ?? []
            guard memberIDs.count == numerators.count,
                  memberIDs.count == denominators.count,
                  !memberIDs.isEmpty,
                  denominators.allSatisfy({ $0 != 0 }) else {
                throw RecordMappingError.claimArrayMismatch(itemID: itemID)
            }
            let claims = zip(memberIDs, zip(numerators, denominators)).map { memberID, fraction in
                Claim(itemID: itemID, memberID: memberID, portion: Fraction(fraction.0, fraction.1))
            }
            return .claimed(claims)
        default:
            throw RecordMappingError.invalidValue(
                recordType: record.recordType,
                field: RecordSchema.ItemType.claimKind
            )
        }
    }

    // MARK: - Field helpers

    private static func uuid(fromRecordName name: String) throws -> UUID {
        guard let id = UUID(uuidString: name) else {
            throw RecordMappingError.invalidRecordName(name)
        }
        return id
    }

    private static func string(_ record: CKRecord, _ key: String) throws -> String {
        guard let value = record[key] as? String else {
            throw RecordMappingError.missingField(recordType: record.recordType, field: key)
        }
        return value
    }

    private static func date(_ record: CKRecord, _ key: String) throws -> Date {
        guard let value = record[key] as? Date else {
            throw RecordMappingError.missingField(recordType: record.recordType, field: key)
        }
        return value
    }

    private static func uuidField(_ record: CKRecord, _ key: String) throws -> UUID {
        guard let id = UUID(uuidString: try string(record, key)) else {
            throw RecordMappingError.invalidValue(recordType: record.recordType, field: key)
        }
        return id
    }

    private static func rawValue<T: RawRepresentable>(
        _ type: T.Type,
        _ record: CKRecord,
        _ key: String
    ) throws -> T where T.RawValue == String {
        guard let value = T(rawValue: try string(record, key)) else {
            throw RecordMappingError.invalidValue(recordType: record.recordType, field: key)
        }
        return value
    }

    private static func intValue(_ record: CKRecord, _ key: String) -> Int {
        (record[key] as? Int) ?? Int(record[key] as? Int64 ?? 0)
    }
}
