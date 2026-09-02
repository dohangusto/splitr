import Foundation
import Observation
import SplitBillCore
import MultipeerConnectivity
import UIKit

struct RoomPackage: Codable {
    var room: Room
    var photos: [String: String]
}

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

    private static var isRunningTests: Bool {
        NSClassFromString("XCTest") != nil
    }

    private static var fileURL: URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("rooms.json")
    }

    private static func loadPersistentRooms() -> [Room] {
        guard !isRunningTests else { return [] }
        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode([Room].self, from: data)
        } catch {
            return []
        }
    }

    private func save() {
        guard !Self.isRunningTests else { return }
        do {
            let data = try JSONEncoder().encode(rooms)
            try data.write(to: Self.fileURL)
        } catch {
            print("Failed to save rooms: \(error)")
        }
    }

    init(rooms: [Room] = []) {
        if rooms.isEmpty {
            self.rooms = Self.loadPersistentRooms()
        } else {
            self.rooms = rooms
        }
    }

    func room(withID id: UUID) -> Room? {
        ensureSyncSession(for: id)
        return rooms.first { $0.id == id }
    }

    func actingMemberID(in roomID: UUID) -> UUID? {
        if !Self.isRunningTests,
           let actingStr = UserDefaults.standard.string(forKey: "splitr.acting_member_\(roomID.uuidString)"),
           let acting = UUID(uuidString: actingStr) {
            return acting
        }
        if let acting = actingByRoom[roomID] {
            return acting
        }
        if let inviteMemberStr = UserDefaults.standard.string(forKey: "splitr.invite_member_\(roomID.uuidString)"),
           let memberID = UUID(uuidString: inviteMemberStr) {
            return memberID
        }
        return room(withID: roomID)?.hostMemberID
    }

    func setActingMember(_ memberID: UUID, in roomID: UUID) {
        actingByRoom[roomID] = memberID
        if !Self.isRunningTests {
            UserDefaults.standard.set(memberID.uuidString, forKey: "splitr.acting_member_\(roomID.uuidString)")
        }
        
        if let index = rooms.firstIndex(where: { $0.id == roomID }) {
            let currentRoom = rooms[index]
            if !currentRoom.members.contains(where: { $0.id == memberID }) {
                let name = UserProfile.currentDisplayName()
                let emoji = UserProfile.load().avatar
                let newMember = Member(id: memberID, displayName: name, avatarEmoji: emoji, isHost: false)
                var updatedMembers = currentRoom.members
                updatedMembers.append(newMember)
                
                let merged = Room(
                    rehydrating: currentRoom.id,
                    name: currentRoom.name,
                    state: currentRoom.state,
                    hostMemberID: currentRoom.hostMemberID,
                    createdAt: currentRoom.createdAt,
                    members: updatedMembers,
                    bills: currentRoom.bills
                )
                rooms[index] = merged
                save()
            }
        }
    }

    // MARK: - Intents

    @discardableResult
    func createRoom(named name: String, hostName: String, hostEmoji: String) -> Room {
        let host = Member(displayName: hostName, avatarEmoji: hostEmoji, isHost: true)
        let room = Room(name: name, host: host)
        rooms.insert(room, at: 0)
        setActingMember(host.id, in: room.id)
        save()
        return room
    }

    func joinMember(named name: String, emoji: String, roomID: UUID) {
        mutate(roomID) { room, _ in
            try room.join(Member(displayName: name, avatarEmoji: emoji))
        }
    }

    func joinFromInvite(named name: String, emoji: String, roomID: UUID) {
        guard let index = rooms.firstIndex(where: { $0.id == roomID }) else { return }
        let defaults = UserDefaults.standard
        let key = "splitr.invite_member.\(roomID.uuidString)"
        let memberID = defaults.string(forKey: key).flatMap(UUID.init) ?? UUID()
        defaults.set(memberID.uuidString, forKey: key)
        defaults.set(memberID.uuidString, forKey: "splitr.acting_member_\(roomID.uuidString)")
        actingByRoom[roomID] = memberID
        
        let currentRoom = rooms[index]
        var members = currentRoom.members
        if !members.contains(where: { $0.id == memberID }) {
            let member = Member(id: memberID, displayName: name, avatarEmoji: emoji, isHost: false)
            members.append(member)
            
            let updated = Room(
                rehydrating: currentRoom.id,
                name: currentRoom.name,
                state: currentRoom.state,
                hostMemberID: currentRoom.hostMemberID,
                createdAt: currentRoom.createdAt,
                members: members,
                bills: currentRoom.bills
            )
            rooms[index] = updated
            save()
        }
        
        setActingMember(memberID, in: roomID)
        ensureSyncSession(for: roomID)
        if let r = room(withID: roomID) {
            syncSessions[roomID]?.sendRoom(r)
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

    func releaseClaim(itemID: UUID, billID: UUID, roomID: UUID) {
        mutate(roomID) { room, actor in
            try room.releaseClaim(itemID: itemID, in: billID, as: actor)
        }
    }

    func joinClaim(itemID: UUID, billID: UUID, roomID: UUID) {
        mutate(roomID) { room, actor in
            try room.joinClaim(itemID: itemID, in: billID, as: actor)
        }
    }

    func forceAssign(itemID: UUID, billID: UUID, to memberID: UUID, roomID: UUID) {
        mutate(roomID) { room, actor in
            try room.forceAssign(itemID: itemID, in: billID, to: memberID, by: actor)
        }
    }

    func toggleClaim(itemID: UUID, billID: UUID, for memberID: UUID, roomID: UUID) {
        mutate(roomID) { room, _ in
            try room.toggleClaim(itemID: itemID, in: billID, for: memberID)
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
            return URL(string: "splitr://room?id=\(roomID.uuidString)")
        }
        
        var photos: [String: String] = [:]
        for bill in room.bills {
            if let ref = bill.photoReference,
               let img = ReceiptPhotoStore.load(ref) {
                let maxDim: CGFloat = 800
                let size = img.size
                let scaledImage: UIImage
                if size.width > maxDim || size.height > maxDim {
                    let ratio = min(maxDim / size.width, maxDim / size.height)
                    let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)
                    UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
                    img.draw(in: CGRect(origin: .zero, size: newSize))
                    scaledImage = UIGraphicsGetImageFromCurrentImageContext() ?? img
                    UIGraphicsEndImageContext()
                } else {
                    scaledImage = img
                }
                
                if let jpeg = scaledImage.jpegData(compressionQuality: 0.5) {
                    photos[ref] = jpeg.base64EncodedString()
                }
            }
        }
        
        let pkg = RoomPackage(room: room, photos: photos)
        var dataBase64 = ""
        if let encoded = try? JSONEncoder().encode(pkg) {
            dataBase64 = encoded.base64EncodedString()
        }
        
        var components = URLComponents()
        components.scheme = "splitr"
        components.host = "room"
        components.queryItems = [
            URLQueryItem(name: "id", value: roomID.uuidString),
            URLQueryItem(name: "name", value: room.name),
            URLQueryItem(name: "hostName", value: host.displayName),
            URLQueryItem(name: "hostEmoji", value: host.avatarEmoji),
            URLQueryItem(name: "data", value: dataBase64)
        ]
        
        return components.url
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
        
        let name = UserProfile.currentDisplayName()
        let emoji = UserProfile.load().avatar
        
        let defaults = UserDefaults.standard
        let key = "splitr.invite_member.\(roomID.uuidString)"
        let memberID = defaults.string(forKey: key).flatMap(UUID.init) ?? UUID()
        defaults.set(memberID.uuidString, forKey: key)
        defaults.set(memberID.uuidString, forKey: "splitr.acting_member_\(roomID.uuidString)")
        actingByRoom[roomID] = memberID
        
        // If full room data is attached, rehydrate the entire room with bills and photos
        if let rawDataString = queryItems.first(where: { $0.name == "data" })?.value {
            let cleanBase64 = rawDataString.replacingOccurrences(of: " ", with: "+")
            if let data = Data(base64Encoded: cleanBase64) {
                var decodedRoom: Room?
                var packagePhotos: [String: String] = [:]
                
                if let pkg = try? JSONDecoder().decode(RoomPackage.self, from: data) {
                    decodedRoom = pkg.room
                    packagePhotos = pkg.photos
                } else if let r = try? JSONDecoder().decode(Room.self, from: data) {
                    decodedRoom = r
                }
                
                if let decodedRoom {
                    // Save all receipt photos to local storage on receiver's phone!
                    for (ref, photoBase64) in packagePhotos {
                        let cleanPhoto = photoBase64.replacingOccurrences(of: " ", with: "+")
                        if let photoData = Data(base64Encoded: cleanPhoto) {
                            ReceiptPhotoStore.saveData(photoData, reference: ref)
                        }
                    }
                    
                    var members = decodedRoom.members
                    if !members.contains(where: { $0.id == memberID }) {
                        let joiner = Member(id: memberID, displayName: name, avatarEmoji: emoji, isHost: false)
                        members.append(joiner)
                    }
                    
                    let mergedRoom = Room(
                        rehydrating: decodedRoom.id,
                        name: decodedRoom.name,
                        state: decodedRoom.state,
                        hostMemberID: decodedRoom.hostMemberID,
                        createdAt: decodedRoom.createdAt,
                        members: members,
                        bills: decodedRoom.bills
                    )
                    
                    if let existingIndex = rooms.firstIndex(where: { $0.id == roomID }) {
                        rooms[existingIndex] = mergedRoom
                    } else {
                        rooms.insert(mergedRoom, at: 0)
                    }
                    
                    setActingMember(memberID, in: roomID)
                    ensureSyncSession(for: roomID)
                    syncSessions[roomID]?.sendRoom(mergedRoom)
                    save()
                    return true
                }
            }
        }
        
        let roomName = queryItems.first(where: { $0.name == "name" })?.value ?? "Bill"
        let hostName = queryItems.first(where: { $0.name == "hostName" })?.value ?? "Host"
        let hostEmoji = queryItems.first(where: { $0.name == "hostEmoji" })?.value ?? "👑"
        
        let host = Member(displayName: hostName, avatarEmoji: hostEmoji, isHost: true)
        let joiner = Member(id: memberID, displayName: name, avatarEmoji: emoji, isHost: false)
        let newRoom = Room(
            rehydrating: roomID,
            name: roomName,
            state: .open,
            hostMemberID: host.id,
            createdAt: Date(),
            members: [host, joiner],
            bills: []
        )
        
        if let existingIndex = rooms.firstIndex(where: { $0.id == roomID }) {
            rooms[existingIndex] = newRoom
        } else {
            rooms.insert(newRoom, at: 0)
        }
        
        setActingMember(memberID, in: roomID)
        ensureSyncSession(for: roomID)
        syncSessions[roomID]?.sendRoom(newRoom)
        save()
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
        try? FileManager.default.removeItem(at: Self.fileURL)
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
            save()
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
            session.onPeerConnected = { [weak self] in
                guard let self = self else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    if let room = self.room(withID: roomID) {
                        self.syncSessions[roomID]?.sendRoom(room)
                    }
                }
            }
            session.start()
            syncSessions[roomID] = session
        }
    }

    private func updateRoomLocally(_ receivedRoom: Room) {
        if let index = rooms.firstIndex(where: { $0.id == receivedRoom.id }) {
            let currentRoom = rooms[index]
            var mergedMembers = currentRoom.members
            var didAddMember = false
            
            for member in receivedRoom.members {
                if !mergedMembers.contains(where: { $0.id == member.id }) {
                    mergedMembers.append(member)
                    didAddMember = true
                }
            }
            
            let updatedBills = receivedRoom.bills.isEmpty ? currentRoom.bills : receivedRoom.bills
            let updatedState = (currentRoom.state == .closed || receivedRoom.state == .closed) ? RoomState.closed : ((currentRoom.state == .settling || receivedRoom.state == .settling) ? .settling : ((currentRoom.state == .claiming || receivedRoom.state == .claiming) ? .claiming : currentRoom.state))
            
            let mergedRoom = Room(
                rehydrating: currentRoom.id,
                name: currentRoom.name,
                state: updatedState,
                hostMemberID: currentRoom.hostMemberID,
                createdAt: currentRoom.createdAt,
                members: mergedMembers,
                bills: updatedBills
            )
            
            rooms[index] = mergedRoom
            save()
            
            if didAddMember {
                syncSessions[receivedRoom.id]?.sendRoom(mergedRoom)
            }
        } else {
            rooms.insert(receivedRoom, at: 0)
            save()
        }
    }

    func deleteRoom(roomID: UUID) {
        rooms.removeAll { $0.id == roomID }
        save()
    }

}

final class MockRoomSyncSession: NSObject, MCSessionDelegate, MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate, @unchecked Sendable {
    let roomID: UUID
    let localPeerID: MCPeerID
    let session: MCSession
    let advertiser: MCNearbyServiceAdvertiser
    let browser: MCNearbyServiceBrowser
    
    var onReceiveRoom: ((Room) -> Void)?
    var onPeerConnected: (() -> Void)?
    
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
            var photos: [String: String] = [:]
            for bill in room.bills {
                if let ref = bill.photoReference,
                   let img = ReceiptPhotoStore.load(ref),
                   let jpeg = img.jpegData(compressionQuality: 0.5) {
                    photos[ref] = jpeg.base64EncodedString()
                }
            }
            let pkg = RoomPackage(room: room, photos: photos)
            let data = try JSONEncoder().encode(pkg)
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
        if state == .connected {
            DispatchQueue.main.async { [weak self] in
                self?.onPeerConnected?()
            }
        }
    }
    
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        var receivedRoom: Room?
        if let pkg = try? JSONDecoder().decode(RoomPackage.self, from: data) {
            for (ref, photoBase64) in pkg.photos {
                let cleanPhoto = photoBase64.replacingOccurrences(of: " ", with: "+")
                if let photoData = Data(base64Encoded: cleanPhoto) {
                    ReceiptPhotoStore.saveData(photoData, reference: ref)
                }
            }
            receivedRoom = pkg.room
        } else if let room = try? JSONDecoder().decode(Room.self, from: data) {
            receivedRoom = room
        }
        if let receivedRoom {
            onReceiveRoom?(receivedRoom)
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
            browser.invitePeer(peerID, to: session, withContext: nil, timeout: 15)
        }
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}
}
