# Moonlit iOS

Moonlit is a private, moon-themed photo diary for two people. Phase 2 adds anonymous Supabase authentication, invitation-code pairing, private photos, synchronized moments, reactions, and replies while retaining the v0.1 capture flow and visual design.

Current feature checkboxes and remaining verification gates: [Phase 2 status](Docs/Phase-2-Status.md). The source implementation is committed; shared features still need a macOS build and Supabase/two-device validation before release.

## Phase 2 behavior

- Anonymous Supabase session restored on launch; a new identity is created only when no session exists.
- One couple per user and a database-enforced maximum of two members.
- Twelve-character, single-use pairing codes that expire after 24 hours; only a SHA-256 digest is stored.
- Private `moment-photos` Storage bucket with RLS tied to an exact authorized moment path.
- Durable local drafts and idempotent `begin → upload → finalize` moment publishing.
- Private Realtime invalidations followed by a canonical authorized refetch.
- One replaceable reaction per user per moment and chronological replies.
- Local v0.1 metadata is preserved and migrated into a pending local cache. It is uploaded only after pairing and an explicit “Share earlier moments” action in Settings.
- Local notification reminders remain available.

Anonymous access belongs to the current installation. Do not add a sign-out control until account linking/recovery exists. Private Supabase storage provides authenticated transport and access control; this release does not claim end-to-end encryption.

## Repository layout

```text
Moonlit/                 SwiftUI application
MoonlitTests/            unit tests
Config/                  safe configuration template
supabase/migrations/     schema, functions, RLS, Storage and Realtime policy
supabase/functions/      pairing Edge Function
supabase/tests/          database and integration security checks
Docs/                    source review and Phase 2 implementation plan
Releases/                original v0.1 source archive
project.yml              XcodeGen project definition
```

## Configure without committing keys

Copy `Config/Supabase.example.xcconfig` to `Config/Supabase.local.xcconfig`. Keep the `$()` URL escape used by the template and replace the placeholders locally:

```xcconfig
SUPABASE_URL = https:$()/YOUR_PROJECT_REF.supabase.co
SUPABASE_PUBLISHABLE_KEY = YOUR_PUBLISHABLE_KEY
```

The local file and common secret/signing formats are ignored by Git. The repository intentionally contains no real API key, password, certificate, private key, or provisioning profile. Never place a secret/service-role key in the iOS app.

## Supabase setup

Install the Supabase CLI and a Docker-compatible container runtime. Then, from the repository root:

```bash
supabase start
supabase db reset
supabase functions serve pairing
supabase test db supabase/tests/database/phase2_rls.test.sql
```

For a hosted project:

1. Create or select a dedicated Supabase project.
2. Enable anonymous sign-ins and configure CAPTCHA/abuse protection before public distribution.
3. Configure Realtime to allow private channels only.
4. Link the CLI, review the target, apply migrations, and deploy the function:

   ```bash
   supabase link --project-ref YOUR_PROJECT_REF
   supabase db push
   supabase functions deploy pairing
   ```

5. Run the database tests and the cross-account checks in `supabase/tests/integration/README.md` against a disposable test project before production.

Pairing mutations run through the Edge Function. Its backend-only RPCs are explicitly unavailable to `anon` and `authenticated`; the function verifies the caller's JWT before using its runtime-provided server credential.

## Build on macOS

The project targets iOS 17 and pins `supabase-swift` 2.55.1. That package declares `swift-tools-version: 6.1`, so use Xcode 16.3 or newer to resolve it.

```bash
brew install xcodegen
xcodegen generate
open Moonlit.xcodeproj
```

Choose a development team and a unique bundle identifier if Xcode requests them. Run the `Moonlit` scheme on an iPhone Simulator, then test camera, notification, storage, and two-person synchronization on two real iPhones. Signing certificates and provisioning profiles must stay outside Git.

## Required release checks

- The app builds and unit tests pass on the supported Xcode/iOS SDK.
- Two fresh anonymous users can pair; a concurrent third join fails.
- An unrelated user and another couple cannot query database rows, download guessed photo paths, or join the private Realtime topic.
- Upload interruption at reservation, object upload, and finalization recovers without duplicate moments.
- A corrupt local metadata file is quarantined and is not overwritten.
- Relaunch, offline drafts, reaction/reply retries, Realtime reconnect, camera denial, and notification cold-launch routing are verified.
- Staged files, reachable Git history, and the decompressed release archive pass credential and signing-material scans.
- GitHub reports the destination repository explicitly as private before any push.

Windows can be used to edit and review the Swift, SQL, and TypeScript source. Native SwiftUI compilation, Simulator/device testing, signing, and archive validation require macOS/Xcode. Supabase database tests require the CLI and a running local stack or dedicated test project.

After staging the intended files, run `powershell -File scripts/verify-release.ps1` to verify the original archive hash and scan tracked source plus decompressed archive entries for credential/signing material.

## Original prototype

The unchanged v0.1 source archive is stored at `Releases/Moonlit-iOS-v0.1.zip` with SHA-256:

`9AE06720AA52DD29900AE0C3ABEABD1751DB62B2DD13173DBA7541BD2B139E9D`
