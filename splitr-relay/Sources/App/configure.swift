import Vapor

private struct SessionStoreKey: StorageKey {
    typealias Value = SessionStore
}

extension Application {
    var sessions: SessionStore {
        guard let store = storage[SessionStoreKey.self] else {
            fatalError("SessionStore not configured — call configure(_:) first")
        }
        return store
    }
}

/// Wires up the in-memory session store and routes. `RELAY_TTL_HOURS`
/// (default 6) bounds how long an idle session lives before it expires.
public func configure(_ app: Application) async throws {
    let ttlHours = Environment.get("RELAY_TTL_HOURS").flatMap(Double.init) ?? 6
    app.storage[SessionStoreKey.self] = SessionStore(ttl: ttlHours * 3600)

    // No global auth middleware: the two-token split is enforced per route
    // inside `SessionStore`, and the AASA fetchers must never be gated.
    try routes(app)
}
