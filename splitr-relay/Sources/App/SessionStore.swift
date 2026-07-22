import Crypto
import Foundation
import SplitBillRelay

/// Why a session lookup failed. Routes map these to HTTP status codes so the
/// `RelayClient` can tell "wrong/expired token" from "you can't drain".
enum SessionError: Error {
    case notFound     // 404 — no such session (bad token or never opened)
    case expired      // 410 — existed, TTL elapsed / closed
    case unauthorized // 401 — host token missing or wrong on a host route
}

/// One live mailbox. The server stores and forwards these fields verbatim; it
/// never inspects prices, resolves claims, or computes settlement. All of that
/// happens in the host app, which drains `pending` and posts back `results`.
private struct Session {
    var snapshot: SnapshotDTO
    var participants: [ParticipantDTO]
    /// FIFO queue of clip ops awaiting the host's drain. Non-destructive read:
    /// ops leave only when the host confirms them via `apply`.
    var pending: [ClaimOpDTO]
    /// Outcomes keyed by opId, for the clip to poll.
    var results: [String: ClaimResultDTO]
    let createdAt: Date
    /// SHA-256 of the host token. The plaintext host token is never stored.
    let hostTokenHash: String
}

/// In-memory, TTL-bounded session storage keyed by `sessionToken`. No database
/// — sessions are ephemeral by design. An actor so concurrent Vapor requests
/// serialize safely without locks.
actor SessionStore {
    private var sessions: [String: Session] = [:]
    private let ttl: TimeInterval

    init(ttl: TimeInterval) {
        self.ttl = ttl
    }

    // MARK: - Lifecycle

    /// Mints a public `sessionToken` and a secret `hostToken`, storing only the
    /// host token's hash. Returns both; the plaintext host token is returned
    /// exactly once and never persisted.
    func open(snapshot: SnapshotDTO) -> OpenSessionResponse {
        let sessionToken = Self.randomToken()
        let hostToken = Self.randomToken()
        sessions[sessionToken] = Session(
            snapshot: snapshot,
            participants: snapshot.participants,
            pending: [],
            results: [:],
            createdAt: Date(),
            hostTokenHash: Self.hash(hostToken)
        )
        return OpenSessionResponse(sessionToken: sessionToken, hostToken: hostToken)
    }

    func close(sessionToken: String, hostToken: String) throws {
        _ = try requireHost(sessionToken, hostToken)
        sessions[sessionToken] = nil
    }

    // MARK: - Clip face (sessionToken only)

    func snapshot(sessionToken: String) throws -> SnapshotDTO {
        try liveSession(sessionToken).snapshot
    }

    func registerParticipant(sessionToken: String, name: String, emoji: String) throws -> String {
        var session = try liveSession(sessionToken)
        let participantId = Self.randomToken(byteCount: 16)
        session.participants.append(
            ParticipantDTO(participantId: participantId, displayName: name, avatarEmoji: emoji)
        )
        sessions[sessionToken] = session
        return participantId
    }

    func enqueue(sessionToken: String, op: ClaimOpDTO) throws {
        var session = try liveSession(sessionToken)
        // Idempotent on opId — a client retry after a dropped ack must not
        // double-queue the same toggle.
        if !session.pending.contains(where: { $0.opId == op.opId }),
           session.results[op.opId] == nil {
            session.pending.append(op)
            sessions[sessionToken] = session
        }
    }

    func result(sessionToken: String, opId: String) throws -> ClaimResultDTO? {
        try liveSession(sessionToken).results[opId]
    }

    // MARK: - Host face (hostToken required)

    func pending(sessionToken: String, hostToken: String) throws -> [ClaimOpDTO] {
        try requireHost(sessionToken, hostToken).pending
    }

    /// Records results and dequeues exactly those opIds. Ops the host didn't
    /// mention stay queued for the next drain.
    func apply(sessionToken: String, hostToken: String, results: [ClaimResultDTO]) throws {
        var session = try requireHost(sessionToken, hostToken)
        for result in results {
            session.results[result.opId] = result
        }
        let applied = Set(results.map(\.opId))
        session.pending.removeAll { applied.contains($0.opId) }
        sessions[sessionToken] = session
    }

    func replaceSnapshot(sessionToken: String, hostToken: String, snapshot: SnapshotDTO) throws {
        var session = try requireHost(sessionToken, hostToken)
        session.snapshot = snapshot
        session.participants = snapshot.participants
        sessions[sessionToken] = session
    }

    // MARK: - Internals

    /// Fetches a non-expired session or throws. Lazily evicts on expiry so a
    /// stale token reports `expired`, not a silent success.
    private func liveSession(_ token: String) throws -> Session {
        guard let session = sessions[token] else { throw SessionError.notFound }
        if Date().timeIntervalSince(session.createdAt) > ttl {
            sessions[token] = nil
            throw SessionError.expired
        }
        return session
    }

    /// Clip-token requests can never reach this: it demands a matching host
    /// token hash, enforcing the two-token split at the storage layer.
    private func requireHost(_ token: String, _ hostToken: String) throws -> Session {
        let session = try liveSession(token)
        guard Self.constantTimeEquals(Self.hash(hostToken), session.hostTokenHash) else {
            throw SessionError.unauthorized
        }
        return session
    }

    // MARK: - Crypto helpers

    /// High-entropy, URL-safe token (base64url, no padding).
    private static func randomToken(byteCount: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        for i in bytes.indices { bytes[i] = .random(in: .min ... .max) }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func hash(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Length-and-content compare that doesn't short-circuit on the first
    /// differing byte — avoids leaking the host token via timing.
    private static func constantTimeEquals(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf8), y = Array(b.utf8)
        guard x.count == y.count else { return false }
        var diff: UInt8 = 0
        for i in x.indices { diff |= x[i] ^ y[i] }
        return diff == 0
    }
}
