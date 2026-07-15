# CLAUDE.md — splitr

## What this app is

**splitr** is an iOS app for splitting restaurant bills among friends. One person (the **host**, called the *penalang*) pays the full bill up front. The app lets everyone else **claim their own items** from a scanned receipt inside a shared **bill room**, then tracks who owes what until everyone has paid the host back.

Built for an Apple Developer Academy challenge (Challenge 4). Target: **iPhone 17, iOS 26.0 minimum**, latest Apple frameworks encouraged.

## Core user flow

1. Host creates a **Room** and invites members. Members join by physically bringing their iPhone close to the host's iPhone (Nearby Interaction "tap to join" gesture), with MultipeerConnectivity as the data channel during onboarding.
2. Host photographs the receipt. **Vision** OCR extracts line items. Host reviews and **edits** the parsed items before publishing (OCR is never trusted blindly — Indonesian receipts are messy).
3. Members claim items. Shared items (e.g. fries for the table) can be split across multiple members with per-person portions. Items with qty > 1 are **split into individual claimable units** (qty 3 → 3 rows).
4. Host can **force-assign** unclaimed items to members.
5. When claiming closes, tax (PB1) and service charge are distributed **proportionally to each member's subtotal** (never per-head). Rounding is to whole rupiah; the rounding remainder is absorbed by the host.
6. Members transfer money manually outside the app, then tap "I've paid". Host confirms "payment received". Both checkmarks = settled for that member.
7. Room closes and becomes read-only history.

Payments are tracking-only. No payment gateway integration, ever.

## Architecture decisions (settled — do not revisit without asking)

- **CloudKit (direct API: CKRecord / CKShare / CKRecordZone / CKSubscription) is the source of truth** for all room state. A Room lives in a custom record zone in the host's private database, shared to members via `CKShare`. This keeps rooms alive after people physically part ways and requires no server we manage.
- **Conflict handling**: rely on CloudKit optimistic locking. A claim that loses a race gets `serverRecordChanged`; surface this to the user as "already claimed by X". Never last-write-wins on claims.
- **NI + MPC are onboarding-only.** Nearby Interaction provides the proximity "tap to join" gesture (distance threshold ~30 cm sustained 1–2 s). MultipeerConnectivity is the transport used to exchange NI discovery tokens and to hand the `CKShare` invitation to the joining device. After joining, all state flows through CloudKit.
- **Only the host advances the room state machine.** Members act *within* states (claim, mark paid). Settling → Claiming rollback is allowed; Closed is final.
- **Identity**: members are represented by a display name + emoji avatar entered at join time, with a host-assigned unique ID. Never depend on Apple ID for displayed identity.
- **No SwiftData–CloudKit sync** ("Host in CloudKit" is off; storage was created as None). Domain models are plain Swift types in SplitBillCore, mapped to/from CKRecord in SplitBillSync. Local-only persistence (drafts, history cache) may be added later without CloudKit mirroring.
- **App Clip is a stretch goal** (guest join → claim → view total). It shapes the module structure now, but no App Clip target work until milestone 6.
- **No `CKSyncEngine`.** Rejected deliberately: it hides per-record save policies, and we require compare-and-swap (`.ifServerRecordUnchanged`) on claim writes so a lost race returns `serverRecordChanged`. We map records ourselves.

## Hard-won constraints (learned on-device — do not undo)

These cost real debugging time. Changing any of them breaks live behavior that hermetic tests will not catch.

- **`CKShare.publicPermission` must be `.readWrite`, set before the share is saved.** Our model is link-based: anyone with the invite link joins as a member; we do not pre-invite specific Apple IDs. CloudKit defaults this to `.none`, which makes every link tap fail with "The owner stopped sharing, or your account doesn't have permission to open it".
- **Only produce the invite URL after the share's save to the server has confirmed.** A URL read from an unsaved share points at a share the server doesn't have.
- **Share acceptance lives on `UIWindowSceneDelegate.windowScene(_:userDidAcceptCloudKitShareWith:)`**, not the app delegate. In a SwiftUI `WindowGroup` app the app-delegate variant is never called; the symptom is a silent no-op after Accept.
- **Hosting requires a healthy iCloud account; joining does not.** Creating a room writes a custom zone to the user's own private database (their quota, their account restrictions); joining reads/writes a zone owned by the host. A user who cannot host can still join perfectly well — **a hosting failure must never block joining**, and the two failures must never share one message.
- **Never swallow a `CKError` behind generic copy.** Always surface the real `CKError.Code` (and `CKAccountStatus` where relevant) with actionable per-case messaging — quota full, managed/restricted account, not signed in, temporarily unavailable, network.
- **Never leave a phantom local-only room** when a room fails to sync. Either don't create it, or mark it failed with a retry — never let it look real.
- **The NI/MPC channel carries exactly three messages**: NI discovery token, joiner identity (name + emoji), and the host's invitation (CKShare URL + host-assigned member UUID). It is not a state channel; room state only ever flows through CloudKit.
- **One host "add people nearby" session serves many joiners sequentially.** The MPC advertiser stays up while the room is `open` or `claiming`; completing a join tears down only that joiner's NI ranging and peer connection — never the advertiser or other peers.

## Module structure (SPM local packages)

- **SplitBillCore** — domain models, business logic, bill math, room state machine. Pure Swift, zero UIKit/SwiftUI/CloudKit imports. Fully unit-testable.
- **SplitBillSync** — CloudKit mapping and sync engine, MultipeerConnectivity session, Nearby Interaction session. Depends on SplitBillCore.
- **splitr app target** — SwiftUI views and view models. Depends on both packages.

Keep this dependency direction strict: Core knows nothing about Sync or UI.

## Data model (domain layer)

- `Room`: id, name, state (`RoomState`), hostMemberID, createdAt, members: [Member], bills: [Bill]
- `Member`: id, displayName, avatarEmoji, isHost, paymentStatus (`none | memberMarkedPaid | hostConfirmed`)
- `Bill`: id, merchantName, photoReference, taxRate, serviceChargeRate, items: [BillItem], createdAt
- `BillItem`: id, name, unitPrice, claimState (`unclaimed | claimed(memberIDs + portions) | forceAssigned(memberID)`) — one row per unit (qty already exploded at parse/edit time)
- `Claim`: itemID, memberID, portion (fraction, defaults to equal split among claimers)
- `RoomState`: `open → claiming → settling → closed` (with settling → claiming rollback)

Settlement math lives in Core as pure functions: per-member subtotal → proportional tax/service allocation → whole-rupiah rounding → host absorbs remainder. Property/unit tests must pin these rules.

## UI layering model

The UI is three layers. Decide where something belongs by **scope** — "does this action belong to the app, to this screen, or to this piece of data?" — not by whether it happens to be a button.

1. **Content layer (innermost)** — the data the user came for, and the controls that belong to a specific piece of that data. Scrolls. Example: claiming an item belongs to that item's row, not to a toolbar.
2. **UI tools layer (outermost)** — floats above content, and splits into two sublayers with different lifetimes:
   - **Tab bar** — global, survives navigation, belongs to the *app*. Putting something here says "relevant everywhere."
   - **Toolbar** — per-screen, changes on every push, belongs to *this screen*. Putting something here says "relevant only here."
   - A **bottom accessory** is a tab-bar citizen: content-aware, but tied to the tab bar's presence — it disappears wherever the tab bar is hidden.
3. **Transient layer** — sheets, alerts, popovers, the keyboard. Overlays both and leaves. The proximity join flow lives here.

Rules:

- **The tools layer floats, but it yields.** It is not static furniture: the tab bar minimizes on scroll, the toolbar adapts, and a bottom accessory moves from `.expanded` to `.inline`. Controls surface when needed and recede when not — never design against that.
- **Do not push actions into the toolbar for tidiness.** An action that belongs to a row, a total, or an empty state belongs in content. A screen's primary paths must be reachable where a first-time user will actually look — for Home, the empty state must present *both* Create and Join, since a user who cannot host still needs Join.
- Content is what the app is for; the tools layer is how to move around it. When in doubt, prefer content.

## Tech conventions

- Swift 6, SwiftUI, `@Observable` view models (no Combine-era ObservableObject unless required).
- Swift Testing (`import Testing`, `#expect`) — not XCTest — for any test that is written.
- **Tests are optional and targeted, not a default deliverable.** Do not blanket-test every new type, and do not treat "add tests" as an automatic part of a task. Write a test only where it earns its keep: pure logic where correctness is not obvious by reading (settlement math, the room state machine and claiming rules, record round-trip mapping, receipt parsing, the tap-to-join detector), and regressions for bugs we actually hit. Skip tests for view code, thin wrappers, glue, and anything requiring hardware or a live network. If unsure whether a test is warranted, ask rather than writing it. Existing tests must keep passing.
- Strict concurrency; domain models are `Sendable`.
- English UI copy. Currency formatted as IDR (Rp), no decimal places.
- Money is `Int` rupiah (never floating point).
- **No XCUITest / UI automation tests.** Verify behavior with Swift Testing unit tests (including against the `RoomStore` and other app-layer types by calling intent methods directly) and console/logic-level checks. UI tests are too slow and flaky for this project's timeline.
- **Never run `git commit`, `git push`, or any git write operation.** Do not stage files. The developer handles all git operations manually. When you reach a stable, reviewable point (e.g. models done, tests passing), say so explicitly — "This is a good commit point: <suggested message>" — and continue or stop as instructed.

## Project configuration (already in place — verify, don't re-add)

Capabilities: iCloud → CloudKit (container `iCloud.com.c4.splitr`), Push Notifications, Background Modes → **Remote notifications only** (the "Uses Nearby Interaction" background mode is deliberately off — joining happens in the foreground).

Info.plist: `CKSharingSupported`, `NSCameraUsageDescription`, `NSNearbyInteractionUsageDescription`, `NSLocalNetworkUsageDescription`, `NSBonjourServices` (`_splitr-join._tcp`, `_splitr-join._udp` — must match the MPC service type `splitr-join`).

Never edit capability or entitlement config directly. If something must change, report exactly what and the developer will do it in Xcode. Assume Xcode is closed while you work.

## Milestones

1. **Core domain** — models, state machine, settlement math, unit tests. No UI, no CloudKit.
2. **Local UI flow** — full room/claim/settle UI against an in-memory mock store.
3. **Vision scanning** — receipt capture, OCR parsing to draft items, mandatory review/edit screen.
4. **CloudKit sync** — real shared-room persistence, conflict handling, subscriptions.
5. **NI + MPC join** — proximity onboarding (requires two physical UWB devices).
6. **App Clip** (stretch) — guest flow.

Do not start a milestone early. Simulator suffices for 1–3; milestones 4–5 need physical devices and a paid developer account.

## Things Claude Code should never do in this repo

- Introduce SwiftData↔CloudKit automatic sync.
- Use floating point for money.
- Let OCR results publish without passing through the edit screen flow.
- Split tax/service per-head instead of proportionally.
- Add third-party dependencies without asking.
- Run `git commit` / `git push` / stage files — git is developer-only.
- Write or run XCUITest / UI automation — use `RoomStore`-level unit tests instead.
- Add tests reflexively — see the testing rule above; they are targeted, not automatic.
- Swallow a `CKError` behind generic copy, or let a hosting failure block joining.
- Send anything but the three defined join messages over NI/MPC.
- Edit capabilities, entitlements, or the pbxproj config yourself.