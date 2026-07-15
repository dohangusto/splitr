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

/// Why this account can't host (write to its own private database).
/// Users hitting these can usually still JOIN rooms — joining writes to the
/// host's shared zone, billed to the host — so hosting failures must never
/// block the join paths.
public enum HostingIssue: Sendable, Equatable {
    /// The user's iCloud storage is full (free 5 GB tier, typically).
    case quotaExceeded
    /// School/work-managed Apple ID with CloudKit restrictions.
    case managedAccount
    case notSignedIn
    /// iCloud itself is flaky right now — retryable.
    case temporarilyUnavailable
    case network
    /// Anything else — carries the CKError code description for display.
    case unknown(String)
}

public enum SyncError: Error {
    /// Lost a claim race (`serverRecordChanged` on the item record).
    case conflict(SyncConflict)
    /// Some other write raced ours; `serverRoom` is the refetched truth.
    case staleState(serverRoom: Room)
    /// Room creation failed for an account-level reason. `ckCode` is the
    /// raw CKError code for on-device debugging.
    case hostingFailed(HostingIssue, ckCode: Int?)
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
    /// Preflight for hosting: nil when this account looks able to host.
    /// Based on `CKAccountStatus`; quota problems only surface on write.
    func hostingIssue() async -> HostingIssue?
    /// Creates the room's custom zone and saves the initial record graph.
    /// Account-level failures throw `SyncError.hostingFailed`.
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
    /// Accepts a share from its invite URL (proximity join hands the URL
    /// over MPC; same acceptance path as tapping the link).
    func acceptShare(from url: URL) async throws
    /// Fetches remote changes after a CloudKit push (the caller parses the
    /// notification payload; it is not Sendable and never crosses into the
    /// engine). Snapshots arrive on `updates`. Returns true on success.
    func fetchRemoteChanges() async -> Bool
    /// Emits authoritative snapshots after remote-driven fetches.
    var updates: AsyncStream<SyncUpdate> { get }
}
