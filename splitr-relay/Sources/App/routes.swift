import SplitBillRelay
import Vapor

extension Request {
    var sessions: SessionStore { application.sessions }
    /// The secret host token, if the caller supplied one. Absence is treated
    /// as an invalid token by the store, so clip-token callers can't drain.
    var hostToken: String { headers.first(name: "X-Splitr-Host-Token") ?? "" }
}

/// Maps storage failures to HTTP. The status codes double as the `RelayClient`'s
/// `RelayError` contract: 404→notFound, 410→expired, 401→unauthorized.
private func abort(_ error: SessionError) -> Abort {
    switch error {
    case .notFound: return Abort(.notFound)
    case .expired: return Abort(.gone)
    case .unauthorized: return Abort(.unauthorized)
    }
}

func routes(_ app: Application) throws {

    // MARK: AASA — App Clip association.
    // Served static, `application/json`, no redirect, and reachable by the
    // `AASA-Bot` / `CFNetwork` fetchers (no middleware gates this route).
    // TEAMID is a config placeholder — the developer fills in the real Apple
    // Developer Team ID; we must not invent one.
    app.get(".well-known", "apple-app-site-association") { _ -> Response in
        let body = #"{ "appclips": { "apps": ["9PP7722MM6.com.c4.splitr.Clip"] } }"#
        let response = Response(status: .ok)
        response.headers.replaceOrAdd(name: .contentType, value: "application/json")
        response.body = .init(string: body)
        return response
    }

    // MARK: - Host routes (hostToken required)

    /// Open a session for one bill snapshot. Mints both tokens.
    app.post("sessions") { req async throws -> OpenSessionResponse in
        let snapshot = try req.content.decode(SnapshotDTO.self)
        return await req.sessions.open(snapshot: snapshot)
    }

    /// Drain queued clip ops (non-destructive; `apply` dequeues).
    app.get("sessions", ":s", "pending") { req async throws -> [ClaimOpDTO] in
        let s = try req.parameters.require("s")
        do { return try await req.sessions.pending(sessionToken: s, hostToken: req.hostToken) }
        catch let e as SessionError { throw abort(e) }
    }

    /// Record outcomes of applied ops and dequeue them.
    app.post("sessions", ":s", "apply") { req async throws -> HTTPStatus in
        let s = try req.parameters.require("s")
        let results = try req.content.decode([ClaimResultDTO].self)
        do { try await req.sessions.apply(sessionToken: s, hostToken: req.hostToken, results: results) }
        catch let e as SessionError { throw abort(e) }
        return .noContent
    }

    /// Replace the stored snapshot (updated claim state / roster after applying).
    app.post("sessions", ":s", "snapshot") { req async throws -> HTTPStatus in
        let s = try req.parameters.require("s")
        let snapshot = try req.content.decode(SnapshotDTO.self)
        do { try await req.sessions.replaceSnapshot(sessionToken: s, hostToken: req.hostToken, snapshot: snapshot) }
        catch let e as SessionError { throw abort(e) }
        return .noContent
    }

    app.delete("sessions", ":s") { req async throws -> HTTPStatus in
        let s = try req.parameters.require("s")
        do { try await req.sessions.close(sessionToken: s, hostToken: req.hostToken) }
        catch let e as SessionError { throw abort(e) }
        return .noContent
    }

    // MARK: - Clip routes (sessionToken in path only)

    app.get("sessions", ":s") { req async throws -> SnapshotDTO in
        let s = try req.parameters.require("s")
        do { return try await req.sessions.snapshot(sessionToken: s) }
        catch let e as SessionError { throw abort(e) }
    }

    app.post("sessions", ":s", "participants") { req async throws -> RegisterParticipantResponse in
        let s = try req.parameters.require("s")
        let body = try req.content.decode(RegisterParticipantRequest.self)
        do {
            let id = try await req.sessions.registerParticipant(
                sessionToken: s, name: body.displayName, emoji: body.avatarEmoji
            )
            return RegisterParticipantResponse(participantId: id)
        } catch let e as SessionError { throw abort(e) }
    }

    app.post("sessions", ":s", "claims") { req async throws -> HTTPStatus in
        let s = try req.parameters.require("s")
        let op = try req.content.decode(ClaimOpDTO.self)
        do { try await req.sessions.enqueue(sessionToken: s, op: op) }
        catch let e as SessionError { throw abort(e) }
        return .accepted
    }

    app.get("sessions", ":s", "results", ":opId") { req async throws -> ClaimResultDTO in
        let s = try req.parameters.require("s")
        let opId = try req.parameters.require("opId")
        do {
            guard let result = try await req.sessions.result(sessionToken: s, opId: opId) else {
                throw Abort(.notFound) // not drained yet → client maps to nil
            }
            return result
        } catch let e as SessionError { throw abort(e) }
    }
}
