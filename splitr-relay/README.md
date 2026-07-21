# splitr-relay

An ephemeral **mailbox** between a member's App Clip and the host's full app.
App Clips can only read CloudKit's *public* database, so a guest claim has no
CloudKit-native write path off the Clip. This server is the sanctioned
exception to splitr's "no server we manage" rule (see `CLAUDE.md`) — and
nothing more.

**It is a dumb mailbox.** It stores and forwards bytes keyed by session token.
It contains **no bill math, no claim resolution, and no CloudKit**. Every claim
is resolved by the host app through the same `RoomStore` claim intent an
installed member uses (Core + CloudKit `.ifServerRecordUnchanged` CAS); the
relay only carries the op there and the result back.

## Wire contract

DTOs are the exact `SplitBillRelay` types (path dependency), so client and
server can never drift. Money is `Int` rupiah everywhere.

## Two-token model

- `sessionToken` — public, high-entropy, travels in the App Clip URL path
  `/room/{sessionToken}`. Grants **clip** routes only.
- `hostToken` — separate secret, returned once from `POST /sessions`, held only
  by the host. Required (via `X-Splitr-Host-Token`) for `pending` / `apply` /
  `snapshot` / `DELETE`. Only its SHA-256 is stored.

A request bearing only a `sessionToken` is structurally unable to drain or
apply.

## Routes

| Route | Token | Purpose |
|---|---|---|
| `POST /sessions` | — (mints both) | open a session for one bill snapshot |
| `GET /sessions/{s}/pending` | host | drain queued clip ops (non-destructive) |
| `POST /sessions/{s}/apply` | host | record results, dequeue those opIds |
| `POST /sessions/{s}/snapshot` | host | replace stored snapshot |
| `DELETE /sessions/{s}` | host | close session |
| `GET /sessions/{s}` | session | fetch snapshot |
| `POST /sessions/{s}/participants` | session | register guest → temp participantId |
| `POST /sessions/{s}/claims` | session | enqueue a join/leave op |
| `GET /sessions/{s}/results/{opId}` | session | poll outcome (404 = not drained yet) |
| `GET /.well-known/apple-app-site-association` | — | AASA JSON, no redirect |

## Config

- `RELAY_PORT` (default `8080`), `RELAY_HOST` (default `0.0.0.0`)
- `RELAY_TTL_HOURS` (default `6`) — idle session lifetime.

## Run (local two-device testing)

```sh
swift run App serve            # binds 0.0.0.0:8080 on the Mac
```

Point `RelayClient(baseURL:)` at the Mac's LAN IP (e.g.
`http://192.168.1.20:8080`). The App Clip invocation URL (a Local Experience
carrying only the `sessionToken`) is **independent** of `baseURL`: invocation
just delivers the token; data traffic goes wherever `baseURL` points. This is
enough to exercise host↔clip end to end on two physical iPhones with no cloud
deploy.

## TEAMID

`Sources/App/routes.swift` serves the AASA with a **`TEAMID` placeholder** in
`TEAMID.com.c4.splitr.Clip`. Replace it with the real Apple Developer Team ID
before deploying — the value is intentionally not invented here.
