import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking // URLSession lives here on Linux
#endif

/// One client, two faces. Host methods carry the secret `hostToken` (in a
/// header); clip methods carry only the public `sessionToken` (in the URL
/// path). A clip is *structurally* unable to reach a host route — it never
/// holds a `hostToken`, and the server enforces the split per route.
///
/// `baseURL` is injected so it can point at a Mac's LAN IP for two-device
/// local testing, or a `*.fly.dev` host later. The invocation URL that
/// launches the App Clip (a Local Experience carrying the `sessionToken`) is
/// independent of `baseURL`: invocation delivers the token, data traffic goes
/// wherever `baseURL` points.
///
/// This is a thin URLSession wrapper (no bill logic), so it is intentionally
/// untested — the mapping in `RelayMapping` is where the round-trip test lives.
public actor RelayClient {
    private let baseURL: URL
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private static let hostTokenHeader = "X-Splitr-Host-Token"

    public init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    // MARK: - Host face (requires hostToken)

    /// Opens a session for one bill snapshot. Returns the public
    /// `sessionToken` (goes in the App Clip URL) and the secret `hostToken`
    /// (kept only here). No token is required to open — this mints both.
    public func openSession(snapshot: SnapshotDTO) async throws -> OpenSessionResponse {
        try await send(
            "sessions", method: "POST", body: snapshot, hostToken: nil, decode: OpenSessionResponse.self
        )
    }

    /// Non-destructive read of queued clip ops. Ops are removed only when the
    /// host confirms them via `applyResults`, so a crash mid-drain loses nothing.
    public func fetchPending(sessionToken: String, hostToken: String) async throws -> [ClaimOpDTO] {
        try await send(
            "sessions/\(esc(sessionToken))/pending",
            method: "GET", body: Empty?.none, hostToken: hostToken, decode: [ClaimOpDTO].self
        )
    }

    /// Records the outcome of applied ops (each already run through the
    /// `RoomStore` claim intent) and dequeues those `opId`s.
    public func applyResults(_ results: [ClaimResultDTO], sessionToken: String, hostToken: String) async throws {
        try await sendVoid(
            "sessions/\(esc(sessionToken))/apply", method: "POST", body: results, hostToken: hostToken
        )
    }

    /// Replaces the stored snapshot after applying (updated claim state / roster).
    public func pushSnapshot(_ snapshot: SnapshotDTO, sessionToken: String, hostToken: String) async throws {
        try await sendVoid(
            "sessions/\(esc(sessionToken))/snapshot", method: "POST", body: snapshot, hostToken: hostToken
        )
    }

    public func closeSession(sessionToken: String, hostToken: String) async throws {
        try await sendVoid(
            "sessions/\(esc(sessionToken))", method: "DELETE", body: Empty?.none, hostToken: hostToken
        )
    }

    // MARK: - Clip face (sessionToken only)

    public func fetchSnapshot(sessionToken: String) async throws -> SnapshotDTO {
        try await send(
            "sessions/\(esc(sessionToken))",
            method: "GET", body: Empty?.none, hostToken: nil, decode: SnapshotDTO.self
        )
    }

    /// Registers a guest; the relay assigns a temporary, relay-scoped id.
    /// The host mints the real CloudKit `Member` when it drains this participant.
    public func registerParticipant(name: String, emoji: String, sessionToken: String) async throws -> String {
        let response = try await send(
            "sessions/\(esc(sessionToken))/participants",
            method: "POST",
            body: RegisterParticipantRequest(displayName: name, avatarEmoji: emoji),
            hostToken: nil,
            decode: RegisterParticipantResponse.self
        )
        return response.participantId
    }

    /// Enqueues a join/leave op. Returns the op's id for later polling.
    public func submitClaim(op: ClaimOpDTO, sessionToken: String) async throws -> String {
        try await sendVoid(
            "sessions/\(esc(sessionToken))/claims", method: "POST", body: op, hostToken: nil
        )
        return op.opId
    }

    /// Polls for an op's outcome. `nil` means the host hasn't drained it yet.
    public func pollResult(opId: String, sessionToken: String) async throws -> ClaimResultDTO? {
        do {
            return try await send(
                "sessions/\(esc(sessionToken))/results/\(esc(opId))",
                method: "GET", body: Empty?.none, hostToken: nil, decode: ClaimResultDTO.self
            )
        } catch RelayError.notFound {
            return nil // not resolved yet
        }
    }

    // MARK: - Transport

    private struct Empty: Codable {}

    private func esc(_ component: String) -> String {
        component.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? component
    }

    private func sendVoid<Body: Encodable>(
        _ path: String, method: String, body: Body?, hostToken: String?
    ) async throws {
        _ = try await performRequest(path: path, method: method, body: body, hostToken: hostToken)
    }

    private func send<Body: Encodable, Response: Decodable>(
        _ path: String, method: String, body: Body?, hostToken: String?, decode: Response.Type
    ) async throws -> Response {
        let data = try await performRequest(path: path, method: method, body: body, hostToken: hostToken)
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw RelayError.decoding(String(describing: error))
        }
    }

    /// Returns the response body; maps status codes and transport failures to
    /// `RelayError`. A 204 yields empty `Data`.
    private func performRequest<Body: Encodable>(
        path: String, method: String, body: Body?, hostToken: String?
    ) async throws -> Data {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        if let hostToken {
            request.setValue(hostToken, forHTTPHeaderField: Self.hostTokenHeader)
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            do {
                request.httpBody = try encoder.encode(body)
            } catch {
                throw RelayError.decoding(String(describing: error))
            }
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw RelayError.network(String(describing: error))
        }

        guard let http = response as? HTTPURLResponse else {
            throw RelayError.network("Non-HTTP response")
        }
        switch http.statusCode {
        case 200...299:
            return data
        case 401, 403:
            throw RelayError.unauthorized
        case 404:
            throw RelayError.notFound
        case 410:
            throw RelayError.expired
        default:
            throw RelayError.server(status: http.statusCode)
        }
    }
}
