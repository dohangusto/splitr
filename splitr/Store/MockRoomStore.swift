import Foundation
import Observation
import SplitBillCore
import MultipeerConnectivity
import UIKit

/// In-memory implementation of `RoomStoring` — used by unit tests, SwiftUI
/// previews, and the simulator (no iCloud account needed).
/// Owns plain `Room` values and funnels every mutation through Core's
/// throwing API; Core errors become `alert` messages.
@Observable
final class MockRoomStore: RoomStoring {
    private(set) var rooms: [Room]
    var alert: StoreAlert?
    /// In-memory data is available immediately.
    let isLoadingRooms = false

    /// Per-room "acting as" member for the debug perspective switcher.
    private var actingByRoom: [UUID: UUID] = [:]

    init(rooms: [Room] = []) {
        self.rooms = rooms
    }

    func room(withID id: UUID) -> Room? {
        ensureSyncSession(for: id)
        return rooms.first { $0.id == id }
    }

    func actingMemberID(in roomID: UUID) -> UUID? {
        if let acting = actingByRoom[roomID],
           room(withID: roomID)?.member(withID: acting) != nil {
            return acting
        }
        return room(withID: roomID)?.hostMemberID
    }

    func setActingMember(_ memberID: UUID, in roomID: UUID) {
        actingByRoom[roomID] = memberID
        
        // If the member is not yet in the room, add them locally to simulate the sync join!
        if let index = rooms.firstIndex(where: { $0.id == roomID }) {
            var room = rooms[index]
            if !room.members.contains(where: { $0.id == memberID }) {
                let name = UserDefaults.standard.string(forKey: "splitr.user_display_name") ?? "Guest"
                let emoji = UserDefaults.standard.string(forKey: "splitr.user_avatar_emoji") ?? "👤"
                let member = Member(id: memberID, displayName: name, avatarEmoji: emoji)
                try? room.join(member)
                rooms[index] = room
            }
        }
    }

    // MARK: - Intents

    @discardableResult
    func createRoom(named name: String, hostName: String, hostEmoji: String) -> Room {
        let host = Member(displayName: hostName, avatarEmoji: hostEmoji, isHost: true)
        let room = Room(name: name, host: host)
        rooms.insert(room, at: 0)
        return room
    }

    func joinMember(named name: String, emoji: String, roomID: UUID) {
        mutate(roomID) { room, _ in
            try room.join(Member(displayName: name, avatarEmoji: emoji))
        }
    }

    func renameRoom(roomID: UUID, to newName: String) {
        mutate(roomID) { room, _ in
            room.name = newName
        }
    }

    func advance(roomID: UUID) {
        mutate(roomID) { room, actor in
            try room.advance(by: actor)
        }
    }

    func rollbackToClaiming(roomID: UUID) {
        mutate(roomID) { room, actor in
            try room.rollbackToClaiming(by: actor)
        }
    }

    func kick(memberID: UUID, roomID: UUID) {
        mutate(roomID) { room, actor in
            try room.kick(memberID: memberID, by: actor)
        }
    }

    func addBill(_ bill: Bill, roomID: UUID) {
        mutate(roomID) { room, actor in
            try room.addBill(bill, by: actor)
        }
    }

    func updateBill(_ bill: Bill, roomID: UUID) {
        mutate(roomID) { room, actor in
            try room.updateBill(bill, by: actor)
        }
    }

    func removeBill(billID: UUID, roomID: UUID) {
        mutate(roomID) { room, actor in
            try room.removeBill(withID: billID, by: actor)
        }
    }

    func claim(itemID: UUID, billID: UUID, roomID: UUID) {
        mutate(roomID) { room, actor in
            try room.claim(itemID: itemID, in: billID, as: actor)
        }
    }

    func joinClaim(itemID: UUID, billID: UUID, roomID: UUID) {
        mutate(roomID) { room, actor in
            try room.joinClaim(itemID: itemID, in: billID, as: actor)
        }
    }

    func releaseClaim(itemID: UUID, billID: UUID, roomID: UUID) {
        mutate(roomID) { room, actor in
            try room.releaseClaim(itemID: itemID, in: billID, as: actor)
        }
    }

    func forceAssign(itemID: UUID, billID: UUID, to memberID: UUID, roomID: UUID) {
        mutate(roomID) { room, actor in
            try room.forceAssign(itemID: itemID, in: billID, to: memberID, by: actor)
        }
    }

    func markPaid(roomID: UUID) {
        mutate(roomID) { room, actor in
            try room.markPaid(as: actor)
        }
    }

    func confirmPayment(of memberID: UUID, roomID: UUID) {
        mutate(roomID) { room, actor in
            try room.confirmPayment(of: memberID, by: actor)
        }
    }

    func inviteURL(roomID: UUID) async -> URL? {
        guard let room = room(withID: roomID),
              let host = room.member(withID: room.hostMemberID) else {
            return URL(string: "splitr-mock-share://room?id=\(roomID.uuidString)")
        }
        let nameEscaped = room.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let hostNameEscaped = host.displayName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let hostEmojiEscaped = host.avatarEmoji.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        
        return URL(string: "splitr-mock-share://room?id=\(roomID.uuidString)&name=\(nameEscaped)&hostName=\(hostNameEscaped)&hostEmoji=\(hostEmojiEscaped)")
    }

    func addMember(_ member: Member, roomID: UUID) {
        mutate(roomID) { room, _ in
            try room.join(member)
        }
    }

    func acceptShare(from url: URL) async -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems,
              let idString = queryItems.first(where: { $0.name == "id" })?.value,
              let roomID = UUID(uuidString: idString) else {
            return false
        }
        
        let roomName = queryItems.first(where: { $0.name == "name" })?.value ?? "Mock Room"
        let hostName = queryItems.first(where: { $0.name == "hostName" })?.value ?? "Host"
        let hostEmoji = queryItems.first(where: { $0.name == "hostEmoji" })?.value ?? "👑"
        
        if room(withID: roomID) == nil {
            let host = Member(displayName: hostName, avatarEmoji: hostEmoji, isHost: true)
            let room = Room(
                rehydrating: roomID,
                name: roomName,
                state: .open,
                hostMemberID: host.id,
                createdAt: Date(),
                members: [host],
                bills: []
            )
            rooms.insert(room, at: 0)
        }
        return true
    }

    func waitForRoom(id: UUID) async -> Bool {
        return room(withID: id) != nil
    }

    func resetAllData() {
        rooms.removeAll()
        alert = nil
        actingByRoom.removeAll()
        syncSessions.values.forEach { $0.stop() }
        syncSessions.removeAll()
    }

    // MARK: - Private

    /// Resolves the acting member, then hands the room to `body` inout.
    /// The actor must be resolved *before* `&rooms[index]` is exclusively
    /// accessed — reading `rooms` inside `body` violates exclusivity.
    private func mutate(_ roomID: UUID, _ body: (inout Room, _ actor: UUID) throws -> Void) {
        guard let index = rooms.firstIndex(where: { $0.id == roomID }) else { return }
        let actor = actingMemberID(in: roomID) ?? rooms[index].hostMemberID
        do {
            try body(&rooms[index], actor)
            syncSessions[roomID]?.sendRoom(rooms[index])
        } catch {
            alert = StoreAlert(message: StoreCopy.message(for: error, in: rooms[index]))
        }
    }

    private var syncSessions: [UUID: MockRoomSyncSession] = [:]

    private func ensureSyncSession(for roomID: UUID) {
        if syncSessions[roomID] == nil {
            let session = MockRoomSyncSession(roomID: roomID)
            session.onReceiveRoom = { [weak self] receivedRoom in
                DispatchQueue.main.async {
                    self?.updateRoomLocally(receivedRoom)
                }
            }
            session.start()
            syncSessions[roomID] = session
        }
    }

    private func updateRoomLocally(_ room: Room) {
        if let index = rooms.firstIndex(where: { $0.id == room.id }) {
            rooms[index] = room
        } else {
            rooms.insert(room, at: 0)
        }
    }

}

final class MockRoomSyncSession: NSObject, MCSessionDelegate, MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate, @unchecked Sendable {
    let roomID: UUID
    let localPeerID: MCPeerID
    let session: MCSession
    let advertiser: MCNearbyServiceAdvertiser
    let browser: MCNearbyServiceBrowser
    
    var onReceiveRoom: ((Room) -> Void)?
    
    private let lock = NSLock()
    private var connectedPeers: Set<MCPeerID> = []
    
    init(roomID: UUID) {
        self.roomID = roomID
        
        let ud = UserDefaults.standard
        let uuidKey = "splitr.device_uuid"
        let uuidStr: String
        if let saved = ud.string(forKey: uuidKey) {
            uuidStr = saved
        } else {
            let fresh = UUID().uuidString.prefix(6)
            ud.set(String(fresh), forKey: uuidKey)
            uuidStr = String(fresh)
        }
        
        let deviceName = "\(UIDevice.current.name) (\(uuidStr))"
        self.localPeerID = MCPeerID(displayName: deviceName)
        self.session = MCSession(peer: localPeerID, securityIdentity: nil, encryptionPreference: .none)
        
        let discoveryInfo = ["sync_room_id": roomID.uuidString]
        self.advertiser = MCNearbyServiceAdvertiser(peer: localPeerID, discoveryInfo: discoveryInfo, serviceType: "splitr-sync")
        self.browser = MCNearbyServiceBrowser(peer: localPeerID, serviceType: "splitr-sync")
        
        super.init()
        
        self.session.delegate = self
        self.advertiser.delegate = self
        self.browser.delegate = self
    }
    
    func start() {
        advertiser.startAdvertisingPeer()
        browser.startBrowsingForPeers()
    }
    
    func stop() {
        advertiser.stopAdvertisingPeer()
        browser.stopBrowsingForPeers()
        session.disconnect()
    }
    
    func sendRoom(_ room: Room) {
        guard !session.connectedPeers.isEmpty else { return }
        do {
            let data = try JSONEncoder().encode(room)
            try session.send(data, toPeers: session.connectedPeers, with: .reliable)
        } catch {
            print("Failed to send room: \(error)")
        }
    }
    
    // MARK: - MCSessionDelegate
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        lock.withLock {
            if state == .connected {
                connectedPeers.insert(peerID)
            } else if state == .notConnected {
                connectedPeers.remove(peerID)
            }
        }
    }
    
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        do {
            let room = try JSONDecoder().decode(Room.self, from: data)
            onReceiveRoom?(room)
        } catch {
            print("Failed to decode received room: \(error)")
        }
    }
    
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: (any Error)?) {}
    
    // MARK: - MCNearbyServiceAdvertiserDelegate
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        invitationHandler(true, session)
    }
    
    // MARK: - MCNearbyServiceBrowserDelegate
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        guard let info = info, info["sync_room_id"] == roomID.uuidString else { return }
        if localPeerID.displayName < peerID.displayName {
            browser.invitePeer(peerID, to: session, withContext: nil, timeout: 10)
        }
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}
}
