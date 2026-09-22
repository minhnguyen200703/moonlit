# Phase 2 integration checks

Run these against a disposable local Supabase stack after `supabase db reset`.

1. Create five anonymous users: couple A/B, outsider C, and couple D/E.
2. Confirm direct calls to pairing internal RPCs fail with A's ordinary access token.
3. Create A's invitation, redeem concurrently from B and C, and assert exactly one succeeds and the couple has exactly two members.
4. Confirm expired, rotated, self-used, malformed, and replayed codes return the same generic unavailable response.
5. Upload A's photo through `begin_moment → Storage upload → finalize_moment`. Confirm B can read it and C/D/E cannot select the row or download/replace/delete the object.
6. Interrupt the flow after each step and retry with the same UUID. Confirm one logical moment and no ready record pointing to a missing object.
7. Confirm A and B can set only their own reaction and create their own reply; C/D/E cannot read or write either.
8. Disconnect B from Realtime, change data from A, reconnect and refetch. Confirm B converges without relying on event replay.
9. Subscribe C to A/B's private `couple:<uuid>` topic and confirm authorization rejects it.
10. Exercise the five-per-account and twenty-per-source pairing attempt limits.

The database pgTAP checks live in `supabase/tests/database`. A production release requires these HTTP/Auth/Storage/Realtime checks as automated tests or recorded two-device evidence.
