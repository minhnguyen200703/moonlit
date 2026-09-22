# Moonlit Phase 2 implementation plan

Prepared on 23 September 2026 from a complete static review of the supplied v0.1 archive. The requested core Phase 2 scope is now implemented in this repository; this document also records later hardening work and release gates that require external infrastructure. Current setup and validation status are in `README.md`. See [Phase-2-Review.md](Phase-2-Review.md) for the original source evidence.

## Outcome and scope

Two people can open Moonlit without providing email/password credentials, pair using a private invitation code, and share photos, Moon Notes, reactions, and replies. Each sees the same server-confirmed diary; unrelated users cannot read or modify its records or photos. Pending work survives ordinary app restarts and temporary connection failures.

Preserve the burgundy/cream visual design, welcome experience, capture/retake flow, moon display, local reminders, and three tabs. Extend the data layer and app state rather than redesigning the app.

The current request takes precedence over `README.md`'s older roadmap. Default exclusions are APNs, `device_tokens`, widgets/App Groups, TestFlight/App Store distribution, Apple/email sign-in, multi-device recovery, E2EE, and multiple couples per account. These can follow after core sharing works. Local reminders continue to work; background push delivery is not promised by foreground Realtime synchronization.

**Proposed product defaults:** one fixed couple per user; one creator while waiting and exactly two members when paired; no self-service replacement of an established partner in this release. Codes expire after 24 hours and are single use. One reaction per user per moment, with replace/remove behavior; chronological, flat replies. Optional Moon Notes are at most 500 characters, replies are 1–2,000 trimmed characters, and JPEG uploads are at most 10 MiB after resizing. Validate these limits in the UI and backend. These defaults can be changed before implementation without changing the overall architecture.

## What changes in the existing project

| Existing component | Planned integration |
| --- | --- |
| `MoonlitApp` / `RootView` | Inject configuration/services; route through session restoration, unpaired, invitation waiting, and paired states; retain pending notification destination. |
| `Moment` | Preserve a `LegacyMoment` decoder matching v0.1. Add distinct database DTOs and a UI model with author ID, couple ID, timestamps, storage path, and delivery state. |
| `MomentStore` | Keep an observable UI-facing store, but delegate network, durable local data, and image processing to injected repositories/services. Fix persistence failures before cloud integration. |
| `CaptureFlowView` / `CameraPicker` | Keep capture/preview/retake; add validated input, async preparation, durable pending state, progress/retry, and safe camera/library branches. |
| `HomeView` / `TimelineView` | Use asynchronous private images, cache and pagination; show “You” or the partner's display name; open a moment detail screen. |
| New pairing views | Create invitation, copy code, enter code, waiting/expired/invalid/full states, rotate/revoke an unused code. |
| New moment detail view | Photo, Moon Note, author/time, reactions, chronological replies, and failed-send recovery. |
| `SettingsView` | Show pairing/session/sync status; fix reminder save semantics; replace local-only prototype copy. |
| `MoonPhase` / `MoonlitTheme` | Reuse; no Supabase coupling. |
| `project.yml` | Add official Supabase Swift package, tested version resolution, generated configuration values, and test targets. |

Use small interfaces such as `AuthService`, `PairingRepository`, `MomentRepository`, `PhotoStorage`, `LocalMomentStore`, and `SyncCoordinator`. Keep Supabase DTOs and errors out of view bodies. Publish observable UI state on the main actor; run file/image/network work asynchronously with cancellation. Use an actor for the sync queue so only one drain runs per identity.

Suggested new files, adapting names to the restored project:

```text
Config/Supabase.example.xcconfig
Moonlit/Core/Configuration/AppConfiguration.swift
Moonlit/Core/Services/ServiceContainer.swift
Moonlit/Core/Auth/AuthService.swift
Moonlit/Core/Auth/KeychainSessionStorage.swift
Moonlit/Core/Pairing/PairingRepository.swift
Moonlit/Core/Moments/MomentRepository.swift
Moonlit/Core/Storage/PhotoStorage.swift
Moonlit/Core/Storage/ImagePipeline.swift
Moonlit/Core/Sync/SyncCoordinator.swift
Moonlit/Core/Sync/PendingOperation.swift
Moonlit/Core/Persistence/LocalMomentStore.swift
Moonlit/Core/Persistence/LegacyMomentImporter.swift
Moonlit/Features/Pairing/...
Moonlit/Features/MomentDetail/...
supabase/config.toml
supabase/migrations/...
supabase/functions/pairing/index.ts
supabase/tests/database/...
supabase/tests/integration/...
scripts/verify-release.ps1
Releases/Moonlit-iOS-v0.1.zip
Releases/README.md
```

## Database contract

Use UUID identifiers and UTC `timestamptz`. Keep app-facing tables in `public` with RLS enabled before client grants. Store invitations, abuse counters, and cleanup jobs in a non-exposed `private` schema with no client table access. Use migrations as the authoritative definition; avoid dashboard-only schema changes.

| Table | Essential columns | Required constraints / behavior |
| --- | --- | --- |
| `couples` | `id`, `created_by`, `status`, `created_at` | Status `waiting` or `active`; created through pairing transaction only. `active` is reached with the second member. No direct client membership/status changes. |
| `couple_members` | `couple_id`, `user_id`, `slot`, `display_name`, `joined_at` | PK `(couple_id,user_id)`; unique `user_id`; unique `(couple_id,slot)`; `slot IN (1,2)`; FKs to couple and Auth user. These enforce at most two distinct members even under concurrency. |
| `private.couple_invitations` | `id`, `couple_id`, `created_by`, `code_hash`, `expires_at`, `consumed_at`, `consumed_by`, `revoked_at` | Unique hash; at most one unconsumed/unrevoked invitation per couple. Explicitly revoke expired predecessors before issuing a replacement. No plaintext code column. |
| `moments` | `id`, `couple_id`, `author_id`, `note`, `storage_path`, `captured_at`, `created_at`, `updated_at`, `upload_state`, `deleted_at` | FK `(couple_id,author_id)` to membership; unique storage path; unique `(couple_id,id)` for child FKs; immutable identity/path/capture fields; allowed state transitions; note limit. |
| `reactions` | `couple_id`, `moment_id`, `user_id`, `emoji`, `is_active`, `updated_at` | Unique `(moment_id,user_id)`; composite FK `(couple_id,moment_id)` and member FK; permitted emoji set; immutable ownership/parent. Removing a reaction sets `is_active=false`. |
| `replies` | `id`, `couple_id`, `moment_id`, `author_id`, `body`, `created_at`, `updated_at`, `deleted_at` | Client UUID for idempotent retries; composite parent/member FKs; trimmed body limit; immutable ownership/parent. Deleted replies no longer expose body content through the UI. |
| `private.pairing_attempts` | caller/window key, attempt count, expiry | Backend-only durable rate limits; persist denied attempts and expire old counters. |
| `private.photo_cleanup_jobs` | object path, moment ID, state, attempts, next retry | Backend-only retryable deletion of abandoned or removed photo objects. |

Index the policy predicates and page queries: membership by user, moments by `(couple_id,captured_at DESC,id DESC)`, replies by `(moment_id,created_at,id)`, reactions by parent/user, invitation hash, and cleanup state/time. Avoid unnecessary indexes on every column.

Server code controls `created_at`/`updated_at`. `captured_at` preserves photo chronology, including legacy imports; it is not an authorization signal. Use `(captured_at,id)` as the stable moment pagination cursor and `(created_at,id)` for replies.

Plan account deletion separately from accidental cascading deletion: deleting an Auth record must not silently destroy the partner's diary or leave retrievable orphan photos. For this fixed-pair release, do not expose an unimplemented account-delete/unpair control; document the operator cleanup procedure and require a lifecycle design before broader distribution.

## Authentication and configuration

1. Enable anonymous sign-ins in the development Supabase project. Use the official Swift client and a single client instance per configured environment.
2. Restore the existing session first. Only call `signInAnonymously` when there is genuinely no usable saved identity. A timeout, offline launch, or refresh failure must not silently create a new account.
3. Use the pinned SDK's session-storage API with an explicit Keychain-backed implementation or verify its Keychain default. Select an appropriate device-only accessibility class and test persistence across app termination. Never store tokens in the JSON diary or logs.
4. Observe auth changes, refresh credentials, and propagate the current identity into the data/sync services. Clear account-scoped caches, cancel pending requests, and unsubscribe when identity changes. Do not automatically submit one account's outbox under another account.
5. Show a recoverable auth-error screen and retain local drafts. Do not include a casual “log out” button for an anonymous identity. Explain that anonymous access may be lost after session loss, reinstall, or moving devices; later account linking is the recovery path, not invitation replay. Supabase distinguishes anonymous Auth users from unauthenticated API callers: anonymous signed-in users use the `authenticated` database role. [Anonymous sign-ins](https://supabase.com/docs/guides/auth/auth-anonymous).
6. Configure Auth abuse controls and a supported CAPTCHA flow before exposing signup publicly; test failures and rate limiting. Verify the actual project's configuration rather than relying on a default rate limit. [Swift anonymous sign-in](https://supabase.com/docs/reference/swift/auth-signinanonymously).

Commit a template containing placeholders only. Supply real values through an ignored local `Config/Supabase.local.xcconfig` or CI configuration injection. Include `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY`; reject missing/placeholder values gracefully. Verify that Xcode configuration parsing preserves the full HTTPS URL, since `//` has special meaning in `.xcconfig` files.

The client publishable key is intended for applications, while secret/service-role credentials have elevated access. RLS must secure requests even when the client key is known. Nevertheless, honor this project's stricter rule by committing **no real API keys**, including publishable keys. Store backend credentials only in the deployment platform's secret store; they must never enter the iOS bundle. [Supabase API keys](https://supabase.com/docs/guides/getting-started/api-keys).

Extend `.gitignore` for local config, `.env` variants with explicit placeholder-template exceptions, Supabase local/temp state, signing material (`*.p8`, `*.p12`, `*.pfx`, `*.pem`, `*.key`, `*.cer`, `*.mobileprovision`, `*.provisionprofile`), generated build products, and user-specific Xcode settings. Do not ignore the requested release ZIP. Verify exclusions with `git check-ignore` and a staged-file audit.

## Pairing protocol and concurrency

Use a small `pairing` Edge Function for create/join/rotate/revoke commands. Verify the supplied user JWT with Supabase Auth; never accept a body-provided user ID as identity. The function invokes narrowly scoped backend-only database functions with the verified user ID. Revoke their execution from `PUBLIC`, `anon`, and `authenticated`; permit only the trusted backend role. This prevents callers bypassing the Edge Function's abuse controls by invoking the join RPC directly. Elevated backend credentials require explicit authorization in every branch. [Securing Edge Functions](https://supabase.com/docs/guides/functions/auth).

**Create:** serialize requests for the caller; reject existing membership; create a waiting couple, slot-1 membership, and invitation in one transaction. Generate 12 uniformly random Crockford Base32 symbols (60 random bits), display them as three groups of four, and store only a SHA-256 digest of the normalized code. Use a cryptographic generator, never a timestamp/random UI helper. Return plaintext once, over HTTPS; omit it from analytics, logs, and error telemetry.

**Join:** normalize/validate the code, apply per-user and trusted-source-IP throttles, and call one database transaction. Serialize operations for the caller and lock the invitation/couple in a documented consistent order. Recheck expiry, revocation, usage, existing membership, and available slot after acquiring locks. Insert slot 2, activate the couple, consume the invitation, and invalidate any other active invitation atomically. The membership constraints are the final defense against a third person or concurrent joins into different couples. PostgreSQL row locks serialize conflicting transactions; pair this with unique constraints, not just a read-then-count check. [PostgreSQL locking](https://www.postgresql.org/docs/current/explicit-locking.html).

**Retry and error behavior:** a lost successful response followed by the same request returns the already-established membership for that same caller. Other callers receive a generic invalid/unavailable-code error. A lost create-code response offers a fresh code through rotation without creating another couple. Never disclose the partner's name, couple ID, or whether another person's code exists on failed attempts.

**Rotation/revocation:** only the waiting couple's creator may replace or revoke its invitation. Rotation and redemption use the same locking order, so an old code cannot join after revocation wins the transaction. Joining your own code is rejected without consuming it.

Initial proposed limits: five failed joins per account per 15 minutes and 20 per trusted source IP per 15 minutes, with server-enforced cooldown and configurable thresholds. Use durable/shared counters, not per-function-instance memory; invalid attempts must persist even when the join fails. Accept client IP only from the hosting platform's trusted forwarding mechanism. Anonymous sign-in controls complement these limits; they do not replace them.

## Access policy contract

“Authenticated” alone is never enough to access a diary. Resolve membership from `auth.uid()` and database records, not user-editable metadata, display names, a submitted `couple_id`, or a client-side filter.

| Resource | Read | Create / change / remove |
| --- | --- | --- |
| `couples` | Current members of that couple | Backend pairing functions only |
| `couple_members` | Members of the same couple | Pairing functions only; optionally a narrowly scoped own-display-name update |
| Invitations and limiter/job tables | No client table access | Trusted backend only |
| `moments` | Own pending rows; both members' ready rows; minimal tombstones needed for reconciliation | Authenticated `begin_moment`, `finalize_moment`, and own-removal RPCs with explicit membership/author checks; no general client update/delete grants |
| `reactions` | Members of the parent moment's couple, for ready/nonremoved parents | Own reaction only; validate parent and membership; update only emoji/active state |
| `replies` | Members of the parent moment's couple, for ready/nonremoved parents | Own reply only; validate parent and membership; restrict edits/removal to author |
| Photo objects | Exact matching authorized moment; partner reads only after finalization | Author inserts reserved path; no overwrite; trusted cleanup deletes |
| Private Realtime topic | Current member of the topic's couple | Database-generated notifications; deny client broadcast writes |

Enable RLS and minimize grants on every exposed table. Test reads and each write operation separately. For permitted direct writes, use both `USING` and `WITH CHECK` as applicable, composite foreign keys, and column privileges/triggers to prevent changing ownership or moving an existing record to a different couple. Keep insert/update DTOs explicit. [Row-level security](https://supabase.com/docs/guides/database/postgres/row-level-security).

A membership helper may use a narrowly scoped `SECURITY DEFINER` function to avoid recursive policies on `couple_members`. It must derive the caller from `auth.uid()`, expose only a membership boolean, have a controlled owner, and live outside exposed API schemas. Harden every elevated function with a fixed/empty `search_path`, schema-qualified references, explicit checks, and explicit execution grants. Default to invoker functions where elevation is unnecessary. [Database function security](https://supabase.com/docs/guides/database/functions).

The iOS app must never use the backend role to make tests or normal access succeed. Security tests must exercise actual `anon` and `authenticated` identities, including two members of another couple.

## Private photo and moment lifecycle

Create a private `moment-photos` bucket with allowed MIME type `image/jpeg` and the chosen size limit. Private-bucket access requires authorization or a time-limited signed URL. [Private buckets](https://supabase.com/docs/guides/storage/buckets/fundamentals).

Use canonical paths of the form `<couple UUID>/<author UUID>/<moment UUID>.jpg`. Store only the path in the database; never store a public or expiring signed URL as the photo identity.

1. Persist the captured image and note in a durable local draft with a stable moment UUID. Resize to a proposed maximum 2,048-pixel long edge, normalize orientation, and encode JPEG away from the main actor. Verify removal of GPS/location metadata from sample outputs.
2. When paired and online, call `begin_moment` to reserve the row and immutable object path. The RPC derives author identity from the session and requires an active couple. A repeated UUID succeeds only for the same logical operation/owner.
3. Upload using the user's session with overwrite/upsert disabled. Storage insert policy checks the bucket, canonical path, active membership, exact pending moment, and current author. Path prefixes alone are insufficient.
4. If the upload response is lost, query the reserved object and reconcile its expected metadata before retrying. Do not generate another moment ID or overwrite an existing object blindly.
5. Call idempotent `finalize_moment`. Verify the reserved object exists with expected size/type and state; publish the row as ready. Only then can the partner read the image/moment. Handle “metadata saved, upload failed” and “upload succeeded, finalization failed” independently.
6. Prefer authenticated downloads through an image service with account/couple-scoped memory/disk caches. If signed URLs become necessary, give them a short lifetime (proposed five minutes), treat them as bearer credentials, never log/persist them, and acknowledge that a previously issued URL can remain usable until expiry.
7. On author removal, tombstone the moment and enqueue server-side object cleanup. Block new reactions/replies to the removed parent. The cleanup worker removes bytes through the Storage API and retries failures; SQL deletion of metadata alone is insufficient.
8. Reconcile abandoned pending rows/objects after a defined upload lease, initially 24 hours. Mark a row as being cleaned under a lock before removing its object so cleanup cannot race finalization. Preserve local drafts and offer an explicit requeue if the remote lease expired.

Storage needs its own operation-specific policies; database row policies do not automatically protect `storage.objects`. Deny object replacement/move and unauthorized deletion even when a caller knows the full path. [Storage access control](https://supabase.com/docs/guides/storage/security/access-control).

For legacy v0.1 data, back up `moments.json` and retain original JPEGs; decode the old format separately. Offer an explicit “Share existing moments with your partner” action. Preserve moment UUIDs, notes, and capture dates, record import progress, and make retries idempotent. The old single `reaction` has no author identity, so retain it only as legacy local state rather than inventing a partner reaction.

## Synchronization, reactions, and replies

Use private Realtime Broadcast notifications as a prompt to refetch authorized state. A database trigger emits a minimal `diary_changed` notification to `couple:<id>` after relevant writes. Send no photo URL, note, reply body, invitation, or old row content in that notification. Use a minimal `realtime.send` payload rather than broadcasting complete rows, with the server private flag and client channel configuration both set to private. [Database Broadcast](https://supabase.com/docs/guides/realtime/broadcast).

Require a private channel and a membership policy on `realtime.messages` scoped to the broadcast extension and the authorized couple topic; deny user-originated broadcasts. Configure private-only channels for this project. Keep diary tables out of the Postgres Changes publication. This avoids relying on raw delete payload authorization; Supabase documents special limitations for delete events. [Realtime authorization](https://supabase.com/docs/guides/realtime/authorization), [database broadcasts](https://supabase.com/docs/guides/realtime/subscribing-to-database-changes), [Postgres Changes limitations](https://supabase.com/docs/guides/realtime/postgres-changes).

Connect/subscribe before the canonical fetch, buffer/coalesce invalidations received while fetching, and fetch again when needed. On foreground, reconnection, auth refresh, and pull-to-refresh, reload membership and the currently cached/visible pages plus the open moment's replies/reactions. Reconcile by stable IDs; remove stale visible records based on canonical results/tombstones. Do not depend on event replay or a device-clock-based “updated since” cursor for correctness. Older unloaded pages can be fetched on demand.

Implement local operation states `queued → preparing → uploading → finalizing → synced`, with explicit retryable/permanent failures. Serialize retries per logical record; use exponential backoff with jitter, bounded attempts, and a manual retry. Stop automatic retries on forbidden access or invalid input. Persist queue transitions; app termination during any step must resume safely.

For reactions, send the desired emoji/active state rather than a non-idempotent “toggle” command. Coalesce repeated pending taps for the same `(moment,user)`. Replies use a stable client UUID and trim/validate text on both sides. Show pending/failed state until acknowledged; keep unsent reply text on failure. An optimistic change must roll back or remain visibly pending if the server rejects it.

Revalidate membership before accessing private content after reconnect. Clear private caches when access is lost, and prevent late results from a previous identity being rendered. Realtime subscription authorization is not a substitute for authorization of each data fetch; even a lingering invalidation must not contain private content. Previously downloaded photos cannot be remotely erased from another person's possession.

## Delivery sequence and acceptance gates

Estimates are planning ranges for focused engineering days, not deadlines. Allow roughly 13–22 days after the development environment is usable; Mac availability, backend access, and real-device issues can add calendar time.

| Milestone | Work and deliverable | Done when | Estimate |
| --- | --- | --- | --- |
| M0: restore baseline | Safely restore the archive's application directory; preserve matching root files; record original ZIP/hash in `Releases/`; reproduce build; fix R1/R2 and camera fallback. | Baseline builds on Mac, existing test passes, persistence-failure regression tests pass, original archive hash is preserved. | 1–2 days |
| M1: foundations/auth | Package/config templates, ignore rules, service interfaces, Keychain session handling, app state routing, legacy format separation. | Relaunch preserves identity; offline/refresh errors do not create a new user; placeholder config fails gracefully; no real keys are staged. | 1–2 days |
| M2: schema/security | Reproducible migrations, constraints/indexes, RLS/grants, private bucket, helper/RPC hardening, initial pgTAP/API tests. | Fresh database reset succeeds; cross-couple reads/writes and ownership reassignment fail under real client roles. | 2–3 days |
| M3: pairing | Verified Edge endpoint, code lifecycle/limiter, locked transactions, create/join/waiting UI. | Two devices pair; concurrent third joins fail; expiry/replay/rotation/self-join and lost-response tests pass. | 2–3 days |
| M4: photos/moments | Durable queue, private upload/finalization, image cache, Home/timeline adapters, explicit legacy import, cleanup worker. | A photo reaches the partner; outsiders cannot retrieve it; every upload interruption resumes without duplicate moments or lost drafts. | 2–4 days |
| M5: live interactions | Broadcast/reconnect reconciliation, detail view, per-user reactions and replies, paging and deletion behavior. | Both phones converge after online changes and offline/restart scenarios; author-only mutation tests pass. | 2–3 days |
| M6: product integration | Reminder/routing fixes, permission recovery, accurate status/copy, accessibility and representative image-load checks. | Manual capture/reminder tests pass on iPhone, notification taps route from all tabs and cold launch, failures have recovery controls. | 1–2 days |
| M7: release verification | Mac build/tests, two-device acceptance, security matrix, secret/archive scan, README/setup guide, private-repo check, local commits and push. | All release gates below pass and remote commit matches the intended local commit. | 2–3 days |

M2 may be prepared while auth interfaces are being designed, but storage or UI work must not be declared secure before database tests pass. Do not implement APNs/widgets to fill time while a core-sharing gate is unresolved.

Suggested commit units: restored v0.1 baseline and original archive; persistence/config/auth; schema/RLS/security tests; pairing backend/UI; private moments/upload queue; sync/reactions/replies; integration fixes and verified release documentation. Use a `codex/phase-2-supabase` branch for implementation unless the repository already has a prescribed workflow.

## Required tests

Use pgTAP/database tests for grants, policies, invariants, and RPCs, and real HTTP/Auth/Storage/Realtime integration tests for behaviors SQL alone cannot establish. Run these against a disposable local or dedicated test project, never production data.

| Scenario | Required result |
| --- | --- |
| Unauthenticated request (`anon`) | No diary, member, invitation, photo, or private-topic access. |
| Signed-in but unpaired user | Can use authorized pairing flow; cannot list couples or access shared content. |
| Members A/B versus outsider C and another couple D/E | A/B share only their data; all cross-couple reads, inserts, edits, deletes, object access, and subscriptions are denied. |
| Forged author, couple, parent, or object path | Backend refuses spoofed identity, mismatched child-parent couple, and reassignment of immutable fields. |
| Invitation brute force, expiry, replay, rotate-versus-join, self-join | Limits persist; failures disclose no partner information; only a valid single redemption succeeds. |
| B and C redeem simultaneously | Exactly one occupies slot 2; total membership never exceeds two. |
| One user joins two couples simultaneously / repeats create | Unique membership and transactional behavior prevent duplicate pairing. |
| Edge bypass | Direct authenticated calls to backend-only pairing functions fail. |
| Session restore/offline/token refresh | Same identity on relaunch; offline/temporary auth failures preserve drafts and never create a replacement account silently. |
| Storage attacks | Guessed URLs/paths, overwrite/move, oversized/disallowed MIME uploads, and partner-photo deletion fail. |
| Upload interruption at every stage | At most one logical moment; no ready row points to an unverified/missing object; retries and cleanup converge. |
| Reaction/reply retry and rapid taps | Stable IDs/keys avoid duplicates; one user cannot edit the other's contribution. |
| Event missed, duplicated, delayed, reconnect after delete | Canonical refresh produces the correct visible diary; no dependence on a continuous socket. |
| Local metadata corruption / disk write failure | Preserve recoverable data; expose failure; do not publish false success or overwrite the old diary. |
| Legacy import twice / app killed during import | Same IDs, no duplicate remote moments, no automatic upload of old private photos. |
| App background, termination, permissions, notification routing | Durable pending work, recoverable permissions, correct capture destination, accurate saved reminder schedule. |

On macOS, run XcodeGen, resolve the pinned package, build and test the iOS Simulator scheme with signing disabled, then run capture/privacy/restart flows on real iPhones. Record Xcode/SDK/package versions and actual results. Windows can support editing and some backend checks when tooling is installed; it cannot validate UIKit/SwiftUI execution here.

## Release and Git safeguards

1. Git already exists; inspect status/history/remotes before changing it. Do not reinitialize destructively or assume an empty remote. Once authenticated access works, inspect its default branch/history and reconcile any existing work without force-pushing.
2. Put the supplied, unchanged archive at `Releases/Moonlit-iOS-v0.1.zip`; document its v0.1 source-archive identity and SHA-256. It is not a signed IPA or a Phase 2 build. Validate archive paths before extraction and exclude the outer wrapper when restoring the project root.
3. Scan source, local config candidates, staged content, reachable commit history, and decompressed release archive entries. Reject real API keys, passwords, tokens, private keys, certificates, and provisioning profiles. Do not log matched secret values. Ignore rules cannot remove already-tracked credentials.
4. Stage the intended source/migrations/tests/templates/docs/archive explicitly, inspect the diff and tracked filenames, and commit only after checks pass. Preserve actual local configuration outside Git.
5. Immediately before pushing, request authenticated metadata for `minhnguyen200703/moonlit` and require an explicit `private: true` or equivalent `PRIVATE` visibility result. A 404, a failed public URL, or a configured Git remote is insufficient. If it is public or visibility is inaccessible, stop the push and report the exact condition; do not silently change repository visibility.
6. Push the implementation branch to the exact requested repository, without force. Verify the remote branch SHA matches the local commit and report the branch/commit plus test results. A merge to the default branch is a separate repository action if the workflow requires it.

Current status: the archive is available, Git is initialized, repository privacy is unverified because the connected metadata request returned 404, and no commit/push occurred in this planning pass.

## Definition of done

- A fresh clone can generate/build the app using documented placeholder configuration and locally supplied values.
- Two separate anonymous identities pair once, and the backend enforces the membership limit under concurrent requests.
- Both users can exchange private photos/Moon Notes, see synchronized moments, and send reactions/replies with durable failure recovery.
- Unauthenticated users, unrelated users, and another couple fail the database, Storage, RPC, and Realtime isolation tests.
- Legacy data remains recoverable and is shared only through the explicit import action.
- Core v0.1 capture, moon display, and local reminders continue working; device validation and remaining limitations are documented.
- The original v0.1 ZIP is in `Releases/`, real credentials/signing files are absent from staged files/history/archive, repository privacy is positively verified, and the intended commit is pushed successfully.

Before implementation, only environment details remain to be supplied or discovered: access to the target Supabase project, a macOS/Xcode test environment, and authenticated access capable of confirming the GitHub repository's visibility. No secrets should be pasted into the plan or committed to resolve these prerequisites.
