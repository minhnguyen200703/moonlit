# Moonlit v0.1 review

Reviewed on 23 September 2026. This document preserves the v0.1 baseline findings that guided the subsequent Phase 2 implementation. Paths and line references in this review describe the original archive; current behavior is documented in the repository `README.md`.

The prototype is a useful UI and local-storage baseline. Phase 2 needs a reliable persistence layer, explicit authentication and pairing state, and a backend that enforces privacy independently of the SwiftUI screens. The implementation plan is in [Phase-2-Plan.md](Phase-2-Plan.md).

## What was inspected

The workspace initially contained four files and an initialized Git repository. The subsequently supplied `Moonlit-iOS-v0.1.zip` contains the complete prototype: 16 files, including 12 application Swift files and one Swift test. All source files were read. The ZIP was inspected directly, without extracting or modifying the application.

Archive SHA-256: `9AE06720AA52DD29900AE0C3ABEABD1751DB62B2DD13173DBA7541BD2B139E9D`.

File names below are relative to the archive's outer `Moonlit/` directory. Line references identify the original archive contents.

| File | Current responsibility / assessment |
| --- | --- |
| `Moonlit/App/MoonlitApp.swift` | Creates a shared `MomentStore`; notification delegate posts an in-process camera event. Needs an injected service container and persistent routing state. |
| `Moonlit/App/RootView.swift` | Welcome flag and three tabs. No auth, configuration, or pairing states. Keep the visual shell and extend routing. |
| `Moonlit/Core/Moment.swift` | Local Codable record with UUID, date, sender name, image filename, and one reaction string. Preserve as a legacy import format. |
| `Moonlit/Core/MomentStore.swift` | JSON metadata plus JPEG files. Central point for the persistence defects below and future repository integration. |
| `Moonlit/Core/MoonPhase.swift` | Self-contained approximate lunar calculation; no backend dependency needed. |
| `Moonlit/Core/MoonlitTheme.swift` | Shared palette and crescent component; reusable as-is for Phase 2 screens. |
| `Moonlit/Core/ReminderService.swift` | Actor wrapping notification authorization and local recurring schedules. Keep separate from cloud synchronization. |
| `Moonlit/Features/Capture/CameraPicker.swift` | UIKit camera/library bridge. Verify fallback and permission behavior on Simulator and a device. |
| `Moonlit/Features/Capture/CaptureFlowView.swift` | Capture, preview, optional note, retake, and synchronous save. Needs durable pending/sending/failed states. |
| `Moonlit/Features/Home/HomeView.swift` | Latest local photo, fixed greeting, moon card, one heart action. Needs author identity, async images, and synchronized reaction state. |
| `Moonlit/Features/Timeline/TimelineView.swift` | Two-column local image grid. Needs pagination, image loading states, and moment detail navigation. |
| `Moonlit/Features/Settings/SettingsView.swift` | Reminder controls and prototype status. Needs accurate pairing/session/sync status and revised copy. |
| `MoonlitTests/MoonPhaseTests.swift` | One reference-new-moon test. No persistence, permission, routing, network, or security tests. |
| `project.yml` | XcodeGen iOS 17 application and unit-test targets; Swift language mode 5.0. No Supabase package/configuration. |
| `.gitignore` | Ignores common build/user files only. Needs local configuration and credential exclusions before implementation. |
| `README.md` | Setup, manual checks, and the original six-step Phase 2 outline. Requires scope and setup updates. |

The README, project configuration, ignore file, and test inside the ZIP exactly match their working-directory copies.

## Findings to fix before or during Phase 2

### R1 — P1: unreadable metadata can lead to loss of the diary index

**Evidence:** `Moonlit/Core/MomentStore.swift:41–49`.

`load()` treats a missing file, a read error, and invalid JSON identically: it returns with an empty array. After a decoding failure, adding a new moment writes this new array over `moments.json`, discarding references to all earlier moments. The image files may remain, but the diary records are lost.

**Change:** distinguish first launch from failed loading; preserve/quarantine unreadable metadata; prevent replacement until recovery is resolved; introduce a versioned format and a backup/import path.

**Acceptance:** a corrupted or temporarily unreadable metadata file is preserved, an actionable error appears, and creating a new moment cannot silently replace the old diary.

### R2 — P1: failed persistence leaves a moment presented as saved

**Evidence:** `Moonlit/Core/MomentStore.swift:21–28`; `Moonlit/Features/Capture/CaptureFlowView.swift:75–80`.

`add()` writes the JPEG and publishes the new array entry before persisting metadata. If metadata writing fails, the caller shows an error but the moment remains in the store. A retry creates another UUID and JPEG. A restart then loses entries whose metadata never reached disk.

**Change:** persist a durable draft/outbox entry before announcing success; use a stable operation ID; stage writes and reconcile failures; clean up abandoned files safely. Keep local-save success separate from cloud-upload success.

**Acceptance:** simulated disk failure cannot produce a false saved state or a second logical moment on retry.

### R3 — P2: reaction failures are silently swallowed

**Evidence:** `Moonlit/Core/MomentStore.swift:35–38`.

The UI changes the reaction and ignores a failed metadata write. The reaction appears saved but can revert after restart. This becomes more visible with network failures in Phase 2.

**Change:** make reaction changes durable, expose pending/failed state, and retry the same desired value idempotently. For cloud data, model reactions separately by moment and author.

**Acceptance:** a failed reaction write is visible and recoverable; repeated taps/retries do not create duplicates or affect the partner's reaction.

### R4 — P2: image work runs synchronously in the UI path

**Evidence:** `Moonlit/Core/MomentStore.swift:4–5,21–32`; `Moonlit/Features/Timeline/TimelineView.swift:19–20`; `Moonlit/Features/Home/HomeView.swift:49`.

The main-actor store encodes JPEGs, writes files, reads images, and rewrites the full JSON collection. Views call the synchronous image loader during rendering. This will scale poorly as the diary grows; no thumbnail sizing or cache is present. The performance impact has not been measured on a device.

**Change:** move file/image processing behind an asynchronous service, generate bounded thumbnails, cache by account/couple/object ID, and page metadata.

**Acceptance:** scrolling a representative diary and saving a large photo do not block interaction; decoded images and memory use remain bounded.

### R5 — P2: reminder settings can differ from the active schedule

**Evidence:** `Moonlit/Features/Settings/SettingsView.swift:4–6,12–23,43–52`; `README.md:68`.

Changing a picker immediately persists its value in `AppStorage`, but it does not reschedule notifications. Rescheduling only happens when “Enable reminders” is pressed. After reminders have been enabled, the UI can show new hours while the old schedule remains active; the README's test checklist implies an automatic update.

**Change:** use explicit “Save reminder schedule” behavior with clear dirty/saved state, or reschedule changes when enabled. Add a disable control and prevent overlapping submissions.

**Acceptance:** displayed saved settings match pending notification requests, including after relaunch and permission denial.

## Risks to verify on macOS/iPhone

These are review observations requiring execution, not reproduced crashes or failed tests.

- **Camera fallback:** `CameraPicker.swift:13–14` chooses `.photoLibrary` when no camera is available but still assigns a camera-specific property. Configure camera settings only in the camera branch; test Simulator fallback, cancellation, denied access, and Settings recovery. Apple documents distinct camera/library modes and source availability checks in [UIImagePickerController](https://developer.apple.com/documentation/uikit/uiimagepickercontroller).
- **Notification routing:** `MoonlitApp.swift:32–35` publishes a transient event; `RootView.swift:20–21` ignores it before welcome completes, and `RootView.swift:78–86` has no selected-tab binding. A cold-start event can arrive before a subscriber exists, and capture presentation depends on the Home view. Store a pending destination at app level and test cold launch, background launch, and every selected tab.
- **Missing-photo presentation:** the timeline omits records whose images fail to load (`TimelineView.swift:20–37`), while Home can show a first-moment empty state even when metadata exists (`HomeView.swift:49,78`). Cloud image failures need placeholders/retry controls, not disappearance of the diary entry.
- **Personalization:** the greeting is fixed to “Good evening, Minh” (`HomeView.swift:38`), and all local moments default to “Me” (`Moment.swift:14`). Resolve “You”/partner labels from authenticated IDs; do not use names as authorization inputs.

## Review of the existing Phase 2 outline

The original order—authentication, database, private storage/sync, notifications, widgets, distribution—is a reasonable broad roadmap, but it is not yet an implementation specification.

| Existing outline | Recommended revision |
| --- | --- |
| Email or Sign in with Apple first | Use anonymous sign-in as requested. Document session loss and later account linking. |
| Table names plus “RLS” | Specify invariants, per-operation grants, policies, immutable fields, indexes, and negative tests. |
| Couple pairing is mentioned without a protocol | Add expiring, single-use invitation codes and an atomic transaction enforcing two members. |
| Replace local persistence with cloud upload | Retain reliable local drafts/cache, explicit import of legacy photos, and a durable retry queue. |
| Realtime metadata sync | Add initial fetch, reconnect reconciliation, idempotency, deletion semantics, and subscription cleanup. |
| APNs, `device_tokens`, widgets, TestFlight | Defer to the next phase by default; they are outside this pass's requested core-sharing scope. |
| Private repository reminder | Make authenticated visibility verification and an archive-aware credential scan release gates. |

Private storage plus access policies does not by itself provide end-to-end encryption. Phase 2 should describe its actual privacy model accurately; a later E2EE design would need client-side key generation, partner key exchange, and recovery decisions.

## Repository and verification status at review time

- Git was initialized on an unborn `main` branch with the requested remote configured.
- GitHub visibility could not be established from the initial metadata request, so the review correctly treated privacy as unverified.
- Xcode, XcodeGen, Swift, Docker, and `psql` were unavailable in the Windows environment, preventing native SwiftUI and local-database execution.

After this review, the v0.1 source was restored, the Phase 2 app/backend/tests were added, and the unchanged archive was placed in `Releases/`. The release checklist in `README.md` is authoritative for current verification status.
