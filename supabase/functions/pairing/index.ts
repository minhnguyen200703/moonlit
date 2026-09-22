import { createClient } from "@supabase/supabase-js";

const JSON_HEADERS = { "content-type": "application/json; charset=utf-8" };
const CODE_ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";

type PairingRequest = {
  action?: "create" | "join";
  code?: string;
  displayName?: string;
};

Deno.serve(async (request) => {
  if (request.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const supabaseURL = Deno.env.get("SUPABASE_URL");
  const publishableKey = Deno.env.get("SUPABASE_PUBLISHABLE_KEY") ?? Deno.env.get("SUPABASE_ANON_KEY");
  const secretKey = Deno.env.get("SUPABASE_SECRET_KEY") ?? Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const authorization = request.headers.get("authorization");
  if (!supabaseURL || !publishableKey || !secretKey || !authorization) {
    return json({ error: "unauthorized" }, 401);
  }

  const userClient = createClient(supabaseURL, publishableKey, {
    global: { headers: { authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: authData, error: authError } = await userClient.auth.getUser();
  if (authError || !authData.user) return json({ error: "unauthorized" }, 401);

  let payload: PairingRequest;
  try {
    payload = await request.json();
  } catch {
    return json({ error: "invalid_request" }, 400);
  }

  const displayName = payload.displayName?.trim() ?? "";
  if (displayName.length < 1 || displayName.length > 40) {
    return json({ error: "invalid_display_name" }, 400);
  }

  const admin = createClient(supabaseURL, secretKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  try {
    if (payload.action === "create") {
      const rawCode = generateCode();
      const codeHash = await sha256(rawCode);
      const { data, error } = await admin.rpc("create_pairing_invitation_internal", {
        p_user_id: authData.user.id,
        p_code_hash: codeHash,
        p_display_name: displayName,
      });
      if (error) throw error;
      return json({
        coupleId: data.couple_id,
        code: formatCode(rawCode),
        expiresAt: data.expires_at,
      });
    }

    if (payload.action === "join") {
      const normalizedCode = normalizeCode(payload.code ?? "");
      if (normalizedCode.length !== 12) return json({ error: "invitation_unavailable" }, 400);

      const sourceIP = trustedSourceIP(request);
      const [userHash, ipHash] = await Promise.all([
        sha256(authData.user.id),
        sha256(sourceIP),
      ]);
      const [userLimit, ipLimit] = await Promise.all([
        admin.rpc("check_pairing_rate_limit_internal", {
          p_kind: "user",
          p_subject_hash: userHash,
          p_limit: 5,
          p_window_seconds: 900,
        }),
        admin.rpc("check_pairing_rate_limit_internal", {
          p_kind: "ip",
          p_subject_hash: ipHash,
          p_limit: 20,
          p_window_seconds: 900,
        }),
      ]);
      if (userLimit.error || ipLimit.error) throw userLimit.error ?? ipLimit.error;
      if (userLimit.data !== true || ipLimit.data !== true) {
        return json({ error: "too_many_attempts" }, 429);
      }

      const { data, error } = await admin.rpc("redeem_pairing_invitation_internal", {
        p_user_id: authData.user.id,
        p_code_hash: await sha256(normalizedCode),
        p_display_name: displayName,
      });
      if (error) return json({ error: "invitation_unavailable" }, 400);
      return json({ coupleId: data.couple_id, status: data.status });
    }

    return json({ error: "invalid_action" }, 400);
  } catch (error) {
    console.error("pairing request failed", error instanceof Error ? error.message : "unknown");
    return json({ error: "pairing_failed" }, 400);
  }
});

function generateCode(): string {
  const random = new Uint8Array(12);
  crypto.getRandomValues(random);
  return Array.from(random, (value) => CODE_ALPHABET[value % CODE_ALPHABET.length]).join("");
}

function normalizeCode(value: string): string {
  return value.toUpperCase().replace(/[^A-Z0-9]/g, "");
}

function formatCode(value: string): string {
  return `${value.slice(0, 4)}-${value.slice(4, 8)}-${value.slice(8, 12)}`;
}

async function sha256(value: string): Promise<string> {
  const bytes = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
}

function trustedSourceIP(request: Request): string {
  return request.headers.get("x-real-ip")
    ?? request.headers.get("x-forwarded-for")?.split(",")[0]?.trim()
    ?? "unknown";
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: JSON_HEADERS });
}
