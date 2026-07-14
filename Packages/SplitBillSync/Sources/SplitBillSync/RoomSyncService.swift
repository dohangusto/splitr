import CloudKit
import Foundation
import SplitBillCore

/// A claim race lost against the server: the item is already held by
/// `claimerIDs` and `serverRoom` is the authoritative state to reconcile to.
public struct SyncConflict: Sendable {
    public let itemID: UUID
    public let claimerIDs: [UUID]
    public let serverRoom: Room

    public init(itemID: UUID, claimerIDs: [UUID], serverRoom: Room) {
        self.itemID = itemID
        self.claimerIDs = claimerIDs
        self.serverRoom = serverRoom
    }
}

public enum SyncError: Error {
    /// Lost a claim race (`serverRecordChanged` on the item record).
    case conflict(SyncConflict)
    /// Some other write raced ours; `serverRoom` is the refetched truth.
    case staleState(serverRoom: Room)
    case notSignedIn
    case underlying(Error)
}

/// App-facing alias so app code doesn't need to import CloudKit directly.
public typealias ShareMetadata = CKShare.Metadata

public enum SyncUpdate: Sendable {
    /// Authoritative room snapshots after a remote change or refetch.
    case rooms([Room])
}

/// The persistence boundary the app's CloudKit-backed store talks to.
/// `CloudKitRoomSync` is the real implementation; tests substitute a fake
/// so conflict handling is verifiable without a network.
public protocol RoomSyncService: Sendable {
    /// Account check + subscription setup. Call once at launch.
    func bootstrap() async throws
    /// All rooms visible to this user (own private zones + accepted shares).
    func fetchRooms() async throws -> [Room]
    /// Creates the room's custom zone and saves the initial record graph.
    func create(room: Room) async throws
    /// Persists a mutated room (non-claim intents). Computes the record
    /// diff against the last known server state internally.
    func push(room: Room) async throws
    /// Persists a claim/force-assign/release of one item with an
    /// optimistic-locking save. Throws `SyncError.conflict` on a lost race.
    func pushClaim(room: Room, billID: UUID, itemID: UUID) async throws
    /// Creates (or returns) the zone-wide CKShare and its invitation URL.
    func shareURL(roomID: UUID) async throws -> URL
    /// Accepts a share invitation so the room's zone appears in the
    /// user's shared database.
    func acceptShare(metadata: CKShare.Metadata) async throws
    /// Processes a CloudKit push. Returns true if it triggered a fetch.
    func handleRemoteNotification(userInfo: [AnyHashable: Any]) async -> Bool
    /// Emits authoritative snapshots after remote-driven fetches.
    var updates: AsyncStream<SyncUpdate> { get }
}
