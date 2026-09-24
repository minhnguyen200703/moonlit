# Moonlit Phase 2 status

Reviewed 24 September 2026. **No shared feature is ready for release yet.** The app and backend paths are present in source, but this Windows workspace has no Xcode/iPhone build result and no running Supabase database or deployed project to prove them end to end.

Legend: **✅ Ready** means the artifact was checked here. **🟡 Built** means the source path exists but still needs the stated runtime test. **⬜ Open** means a required step or implementation is missing.

| Feature or deliverable | Status | Evidence and remaining gate |
| --- | --- | --- |
| v0.1 source restored | ✅ Ready | All original Swift source is in `Moonlit/`; the v0.1 archive was inspected and its image directory matches the legacy import path. |
| Original v0.1 release ZIP | ✅ Ready | `Releases/Moonlit-iOS-v0.1.zip` matches SHA-256 `9AE06720AA52DD29900AE0C3ABEABD1751DB62B2DD13173DBA7541BD2B139E9D`. |
| Local Git and private GitHub repository | ✅ Ready | Git was initialized; authenticated GitHub metadata returned `private: true` before the first push; `main` matched the remote commit at that time. Recheck visibility before each later push. |
| Safe configuration template and secret exclusions | ✅ Ready | Placeholder `.xcconfig`, `.gitignore`, tracked-file/archive scan, and ignore-rule checks passed. No real Supabase project values are in the repository. |
| Anonymous authentication | 🟡 Built | `SupabaseGateway.ensureSession()` restores an Auth session or signs in anonymously. Needs a configured project, iOS build, and relaunch/offline identity tests. |
| Couples and two-person membership | 🟡 Built | `couples` and `couple_members` tables, slot and uniqueness constraints, and pairing RPCs exist. Needs migration execution and concurrent-join test. |
| Invitation codes | 🟡 Built | Edge Function generates 12 random symbols, hashes the normalized code, and redeems single-use 24-hour invitations. Deno type-check passed. Needs deployment and create/rotate/expire/replay tests; invitation creation is not rate limited yet. |
| Database row-level security | 🟡 Built | RLS policies and restricted grants exist for couples, members, moments, reactions, and replies. pgTAP source contains 12 assertions, but it has not run against Postgres and does not yet cover the full attack matrix. |
| Private photo uploads | 🟡 Built | Private bucket policy and `begin_moment → upload → finalize_moment` path exist. Needs live Storage metadata, permissions, MIME/size, duplicate upload, and interruption tests. |
| Shared moments and Realtime | 🟡 Built | Canonical refetch, private topic, foreground recovery, local draft queue, and database paging exist. Needs two-device delivery, reconnect, and offline/relaunch tests. |
| Reactions and replies | 🟡 Built | One reaction per user and idempotent reply RPCs exist. A retry in the open detail screen keeps its reply ID; there is no durable reply outbox across app termination. Needs two-device and failure tests. |
| Legacy moment import | 🟡 Built | v0.1 metadata is preserved and sharing requires an explicit Settings action. Added identity-isolation, interruption, and deletion-reconciliation unit cases; Xcode has not run them. |
| Camera, moon display, and local reminders | 🟡 Built | Existing SwiftUI paths remain. Simulator/iPhone permission and notification routing tests are still open. |
| Supabase deployment and project settings | ⬜ Open | No project is linked or configured in this workspace. Apply the migration, deploy `pairing`, enable anonymous sign-in, and require private Realtime channels in a disposable project first. |
| Native build and device acceptance | ⬜ Open | Use Xcode 16.3 or newer for the package's Swift 6.1 tools requirement; generate the project, build/run tests, and exercise two real iPhones on macOS. |
| Database and cross-account security tests | ⬜ Open | Run pgTAP and the HTTP/Auth/Storage/Realtime matrix from `supabase/tests/integration/README.md`. The local database is unavailable here. |

The migration also defines `remove_moment` and a photo cleanup queue, but there is no cleanup worker or deletion UI. Treat deletion as unfinished; do not expose it as a working feature. Account recovery, APNs, widgets, and App Store distribution remain outside the requested core Phase 2 scope.

This review corrected account scoping for local drafts, added complete paged diary fetches and queued refreshes, kept reply IDs stable during retries, exposed retry from an older failed moment, and aligned invitation rotation and redemption lock order. The Realtime delete trigger now reads the correct trigger row. These are source fixes pending the same native and database tests above.

The next release gate is a macOS build plus a disposable Supabase deployment. Only after the two-device and cross-account checks pass should the 🟡 app features be ticked as ready.
