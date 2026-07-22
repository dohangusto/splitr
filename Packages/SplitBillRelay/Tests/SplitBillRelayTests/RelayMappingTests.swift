import Foundation
import Testing
import SplitBillCore
@testable import SplitBillRelay

/// Mirrors SplitBillSync's record round-trip rule: the one place worth a test
/// is Core ⇄ DTO mapping. Pins the two invariants that quietly corrupt data if
/// they regress — money stays `Int`, and every claim-state variant (including
/// exact shared portions) survives the round trip byte-for-byte.
@Suite struct RelayMappingTests {

    /// Round-trips a value through JSON to prove the DTO is not just
    /// structurally equal but wire-stable.
    private func throughJSON<T: Codable & Equatable>(_ value: T) throws -> T {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(T.self, from: data)
    }

    @Test func unclaimedItemRoundTrips() throws {
        let item = BillItem(name: "Es Teh", unitPrice: 8_000)
        let dto = try throughJSON(RelayMapping.itemDTO(from: item))
        let back = try RelayMapping.billItem(from: dto)
        #expect(back == item)
    }

    @Test func forceAssignedItemRoundTrips() throws {
        let assignee = UUID()
        let item = BillItem(name: "Nasi Goreng", unitPrice: 35_000, claimState: .forceAssigned(assignee))
        let dto = try throughJSON(RelayMapping.itemDTO(from: item))
        let back = try RelayMapping.billItem(from: dto)
        #expect(back == item)
        #expect(back.claimState == .forceAssigned(assignee))
    }

    @Test func singleClaimerRoundTrips() throws {
        let itemID = UUID()
        let memberID = UUID()
        let item = BillItem(
            id: itemID, name: "Ayam Bakar", unitPrice: 42_000,
            claimState: .claimed([Claim(itemID: itemID, memberID: memberID, portion: .one)])
        )
        let dto = try throughJSON(RelayMapping.itemDTO(from: item))
        let back = try RelayMapping.billItem(from: dto)
        #expect(back == item)
    }

    @Test func sharedClaimPreservesExactPortions() throws {
        // A three-way split has a portion (1/3) that no float can represent
        // exactly — this is the case the Fraction-on-the-wire design protects.
        let itemID = UUID()
        let ids = [UUID(), UUID(), UUID()]
        let claims = ids.map { Claim(itemID: itemID, memberID: $0, portion: Fraction(1, 3)) }
        let item = BillItem(id: itemID, name: "Kentang Goreng", unitPrice: 25_000, claimState: .claimed(claims))

        let dto = try throughJSON(RelayMapping.itemDTO(from: item))
        let back = try RelayMapping.billItem(from: dto)

        #expect(back == item)
        guard case .claimed(let backClaims) = back.claimState else {
            Issue.record("expected claimed state")
            return
        }
        #expect(backClaims.allSatisfy { $0.portion == Fraction(1, 3) })
        #expect(backClaims.reduce(Fraction.zero) { $0 + $1.portion } == .one)
    }

    @Test func unevenSharedPortionsSurvive() throws {
        let itemID = UUID()
        let a = UUID(), b = UUID()
        let claims = [
            Claim(itemID: itemID, memberID: a, portion: Fraction(2, 3)),
            Claim(itemID: itemID, memberID: b, portion: Fraction(1, 3)),
        ]
        let item = BillItem(id: itemID, name: "Pizza", unitPrice: 90_000, claimState: .claimed(claims))
        let back = try RelayMapping.billItem(from: try throughJSON(RelayMapping.itemDTO(from: item)))
        #expect(back == item)
    }

    @Test func moneyStaysInt() throws {
        // Encode a price that a float would mangle if anyone reached for one.
        let item = BillItem(name: "Kopi", unitPrice: 33_333)
        let data = try JSONEncoder().encode(RelayMapping.itemDTO(from: item))
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("\"unitPrice\":33333"))
        #expect(!json.contains("33333.0"))
        #expect(try RelayMapping.billItem(from: throughJSON(RelayMapping.itemDTO(from: item))).unitPrice == 33_333)
    }

    @Test func fullSnapshotRoundTrips() throws {
        let itemID = UUID()
        let claimerID = UUID()
        let bill = Bill(
            merchantName: "Warung Nasi",
            tax: 3_800,
            serviceCharge: 1_900,
            discount: 500,
            items: [
                BillItem(name: "Teh", unitPrice: 8_000),
                BillItem(
                    id: itemID, name: "Sate", unitPrice: 30_000,
                    claimState: .claimed([Claim(itemID: itemID, memberID: claimerID, portion: .one)])
                ),
            ]
        )
        let members = [
            Member(id: claimerID, displayName: "Budi", avatarEmoji: "🦊", isHost: false),
            Member(displayName: "Sari", avatarEmoji: "🐱", isHost: true),
        ]
        let snapshot = RelayMapping.snapshotDTO(
            sessionId: "sess-1", bill: bill, participants: members, roomState: .claiming
        )
        let back = try throughJSON(snapshot)

        #expect(back == snapshot)
        // Amounts survive exactly (Int rupiah), so the clip's local settlement
        // matches the host's.
        #expect(back.tax == 3_800)
        #expect(back.serviceCharge == 1_900)
        #expect(back.discount == 500)
        #expect(back.roomState == .claiming)
        #expect(back.items.count == 2)
        #expect(back.participants.count == 2)
    }

    @Test func invalidParticipantIDFailsLoudly() throws {
        let dto = ItemDTO(
            id: UUID().uuidString, name: "X", unitPrice: 1_000,
            claimState: .forceAssigned(participantId: "not-a-uuid")
        )
        #expect(throws: RelayMapping.MappingError.self) {
            _ = try RelayMapping.billItem(from: dto)
        }
    }

    @Test func mismatchedPortionCountFailsLoudly() throws {
        let itemID = UUID()
        let dto = ItemDTO(
            id: itemID.uuidString, name: "X", unitPrice: 1_000,
            claimState: .claimed(participantIds: [UUID().uuidString], portions: [Fraction(1, 2), Fraction(1, 2)])
        )
        #expect(throws: RelayMapping.MappingError.self) {
            _ = try RelayMapping.billItem(from: dto)
        }
    }
}
