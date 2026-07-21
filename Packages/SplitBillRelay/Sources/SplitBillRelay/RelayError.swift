import Foundation

/// Typed transport failures. Same spirit as CLAUDE.md's CKError rule: never
/// swallow a failure behind generic copy — each case is actionable and the
/// underlying detail is preserved as a string (so `RelayError` stays
/// `Sendable`; `URLError`/decoding errors are not always `Sendable`).
public enum RelayError: Error, Sendable, Equatable {
    /// Network transport failed (offline, DNS, TLS, timeout). Carries the
    /// underlying description for debugging.
    case network(String)
    /// The session doesn't exist (404) — bad token or never opened.
    case notFound
    /// The session existed but has expired / been closed (410).
    case expired
    /// A clip token tried to reach a host route, or the host token was wrong
    /// (401/403). A `sessionToken` alone must never drain or apply.
    case unauthorized
    /// The response body couldn't be decoded into the expected DTO.
    case decoding(String)
    /// The server returned an unexpected status code.
    case server(status: Int)
}
