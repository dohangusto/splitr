import Foundation
import SplitBillCore

/// Deterministic demo content: one room per `RoomState`, built through
/// Core's own API so every fixture respects the domain invariants.
/// `try!` is deliberate — a crash here means the fixture itself is wrong.
enum MockData {
    static func rooms() -> [Room] {
        [openRoom(), claimingRoom(), settlingRoom(), closedRoom()]
    }

    // MARK: - Open: fresh room, no bills yet (empty-state showcase)

    private static func openRoom() -> Room {
        let host = Member(displayName: "Hano", avatarEmoji: "Avatar1", isHost: true)
        var room = Room(name: "Nongkrong Jumat", host: host)
        try! room.join(Member(displayName: "Dita", avatarEmoji: "Avatar2"))
        try! room.join(Member(displayName: "Raka", avatarEmoji: "Avatar3"))
        return room
    }

    // MARK: - Claiming: shared items, a force-assigned item, unclaimed leftovers

    private static func claimingRoom() -> Room {
        let host = Member(displayName: "Hano", avatarEmoji: "Avatar1", isHost: true)
        let dita = Member(displayName: "Dita", avatarEmoji: "Avatar2")
        let raka = Member(displayName: "Raka", avatarEmoji: "Avatar3")
        let sinta = Member(displayName: "Sinta", avatarEmoji: "Avatar4")
        var room = Room(name: "Makan Malam Tim", host: host)
        try! room.join(dita)
        try! room.join(raka)
        try! room.join(sinta)

        // Qty 2 already exploded into two claimable units upstream.
        let nasi = BillItem(name: "Nasi Goreng Kambing", unitPrice: 55_000)
        let sate1 = BillItem(name: "Sate Ayam (10 tusuk)", unitPrice: 35_000)
        let sate2 = BillItem(name: "Sate Ayam (10 tusuk)", unitPrice: 35_000)
        let kentang = BillItem(name: "Kentang Goreng", unitPrice: 25_000)
        let gurame = BillItem(name: "Gurame Bakar", unitPrice: 85_000)
        let esTeh = BillItem(name: "Es Teh Manis", unitPrice: 10_000)
        let tekko = Bill(
            merchantName: "Warung Tekko",
            tax: 18_000,
            serviceCharge: 9_000,
            discount: 5_000,
            items: [nasi, sate1, sate2, kentang, gurame, esTeh]
        )
        try! room.addBill(tekko, by: host.id)

        // Second bill with no claims at all (empty-claims showcase).
        let kopi = Bill(
            merchantName: "Kopi Kenangan",
            tax: 4_000,
            items: [
                BillItem(name: "Kopi Kenangan Mantan", unitPrice: 22_000),
                BillItem(name: "Americano", unitPrice: 18_000),
            ]
        )
        try! room.addBill(kopi, by: host.id)

        try! room.advance(by: host.id) // → claiming
        try! room.claim(itemID: nasi.id, in: tekko.id, as: host.id)
        try! room.claim(itemID: sate1.id, in: tekko.id, as: dita.id)
        // Fries shared by the whole table.
        try! room.claimShared(
            itemID: kentang.id, in: tekko.id,
            among: [host.id, dita.id, raka.id, sinta.id]
        )
        // Nobody owned up to the gurame; host assigned it.
        try! room.forceAssign(itemID: gurame.id, in: tekko.id, to: raka.id, by: host.id)
        // sate2 and esTeh stay unclaimed.
        return room
    }

    // MARK: - Settling: everything claimed, payments in progress

    private static func settlingRoom() -> Room {
        let host = Member(displayName: "Hano", avatarEmoji: "Avatar1", isHost: true)
        let dita = Member(displayName: "Dita", avatarEmoji: "Avatar2")
        let raka = Member(displayName: "Raka", avatarEmoji: "Avatar3")
        var room = Room(name: "Bakmi GM Siang", host: host)
        try! room.join(dita)
        try! room.join(raka)

        let bakmi1 = BillItem(name: "Bakmi Spesial GM", unitPrice: 32_000)
        let bakmi2 = BillItem(name: "Bakmi Ayam", unitPrice: 28_000)
        let pangsit = BillItem(name: "Pangsit Goreng (isi 6)", unitPrice: 26_000)
        let esJeruk = BillItem(name: "Es Jeruk", unitPrice: 12_000)
        let bill = Bill(
            merchantName: "Bakmi GM Grand Indonesia",
            tax: 15_000,
            serviceCharge: 7_500,
            items: [bakmi1, bakmi2, pangsit, esJeruk]
        )
        try! room.addBill(bill, by: host.id)
        try! room.advance(by: host.id) // → claiming
        try! room.claim(itemID: bakmi1.id, in: bill.id, as: host.id)
        try! room.claim(itemID: bakmi2.id, in: bill.id, as: dita.id)
        try! room.claimShared(itemID: pangsit.id, in: bill.id, among: [host.id, dita.id, raka.id])
        try! room.claim(itemID: esJeruk.id, in: bill.id, as: raka.id)
        try! room.advance(by: host.id) // → settling
        try! room.markPaid(as: dita.id) // Dita paid, waiting for host confirmation
        return room
    }

    // MARK: - Closed: fully settled history entry

    private static func closedRoom() -> Room {
        let host = Member(displayName: "Hano", avatarEmoji: "Avatar1", isHost: true)
        let dita = Member(displayName: "Dita", avatarEmoji: "Avatar2")
        var room = Room(name: "Farewell Mbak Ayu", host: host)
        try! room.join(dita)

        let salmon = BillItem(name: "Salmon Sushi Roll", unitPrice: 68_000)
        let ocha = BillItem(name: "Ocha", unitPrice: 8_000)
        let bill = Bill(
            merchantName: "Sushi Tei Senayan City",
            tax: 12_000,
            serviceCharge: 9_600,
            items: [salmon, ocha]
        )
        try! room.addBill(bill, by: host.id)
        try! room.advance(by: host.id) // → claiming
        try! room.claim(itemID: salmon.id, in: bill.id, as: dita.id)
        try! room.claim(itemID: ocha.id, in: bill.id, as: host.id)
        try! room.advance(by: host.id) // → settling
        try! room.markPaid(as: dita.id)
        try! room.confirmPayment(of: dita.id, by: host.id)
        try! room.advance(by: host.id) // → closed
        return room
    }
}
