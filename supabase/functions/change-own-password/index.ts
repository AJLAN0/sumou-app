// change-own-password — Supabase Edge Function (Sprint 10 Step 10.6A).
//
// A signed-in staff user changes THEIR OWN password. Flow:
//   POST JSON → require Bearer user → authorize (own ACTIVE, non-deleted profile;
//   no admin role / no permission) → validate the new password policy → require it
//   to differ from the current one → derive the hidden internal email (in-function)
//   → RE-AUTHENTICATE the current password with an ISOLATED anon client → update
//   ONLY the caller's Auth password (service_role) → call record_own_password_change
//   (clear must_change_password + audit, atomically) → return a safe summary.
//
// Auth and the public schema cannot share one SQL transaction. Ordering is
// Auth-update BEFORE the RPC. If the RPC fails AFTER the Auth password changed we
// return a GENERIC 500 and do NOT restore the old password (it is not available) —
// the safe retry uses the NEW password as `current_password`. No distributed
// transaction is claimed. Existing sessions are NOT revoked.
//
// Secrets come only from Deno env. Nothing hardcoded. The internal Auth email is
// built here, never accepted, returned, or logged; request bodies, passwords, and
// tokens are never logged.
//
// NOT deployed by this step — the owner deploys to DEV manually.

import {
  createClient,
  type SupabaseClient,
} from "https://esm.sh/@supabase/supabase-js@2.45.4";
import {
  buildInternalEmail,
  isJsonContentType,
  isValidUsername,
  MAX_BODY_BYTES,
  normalizeUsername,
  readBoundedBody,
  validateNewPassword,
  validatePasswordChangeInput,
} from "../_shared/auth-utils.ts";

// The success/error bodies never contain a secret, but responses must never be
// cached or content-sniffed anyway.
const SECURITY_HEADERS: Record<string, string> = {
  "Content-Type": "application/json",
  "Cache-Control": "no-store, max-age=0",
  "Pragma": "no-cache",
  "X-Content-Type-Options": "nosniff",
};

function json(
  body: unknown,
  status: number,
  extra: Record<string, string> = {},
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...SECURITY_HEADERS, ...extra },
  });
}
function errorResponse(
  code: string,
  message: string,
  status: number,
  extra: Record<string, string> = {},
): Response {
  return json({ error: { code, message } }, status, extra);
}

/** Shared generic 500 for any auth-check failure — never leaks the cause. */
const authServerError = {
  ok: false as const,
  status: 500,
  code: "server_error",
  message: "authorization check failed",
};

/**
 * Authorize: authenticated + own ACTIVE, non-deleted profile with a WELL-FORMED
 * identity. NO admin role and NO feature permission are required — any active
 * staff account may change its own password. Returns the caller's uid + the
 * NORMALIZED, validated username so the internal email can be derived in-function.
 *
 * Fail closed: a query error OR a THROWN SDK/network exception → generic 500
 * (never treated as empty). A malformed stored identity (id ≠ uid, or a username
 * that does not match `^[a-z0-9._-]{2,50}$`) → generic 500, BEFORE re-auth and
 * before any service client is built.
 */
export async function authorizeActiveStaff(
  userClient: SupabaseClient,
): Promise<
  { ok: true; uid: string; username: string } | {
    ok: false;
    status: number;
    code: string;
    message: string;
  }
> {
  let userData;
  let userErr;
  try {
    ({ data: userData, error: userErr } = await userClient.auth.getUser());
  } catch {
    return {
      ok: false,
      status: 500,
      code: "server_error",
      message: "authorization check failed",
    };
  }
  if (userErr || !userData?.user) {
    return {
      ok: false,
      status: 401,
      code: "unauthenticated",
      message: "invalid or missing session",
    };
  }
  const uid = userData.user.id;

  // The profiles self-read policy returns the row ONLY when active + not
  // soft-deleted, so a missing row means inactive/deleted/absent → reject.
  let profileRes;
  try {
    profileRes = await userClient
      .from("profiles").select("id, is_active, username").eq("id", uid)
      .maybeSingle();
  } catch {
    return {
      ok: false,
      status: 500,
      code: "server_error",
      message: "authorization check failed",
    };
  }
  if (profileRes.error) {
    return {
      ok: false,
      status: 500,
      code: "server_error",
      message: "authorization check failed",
    };
  }
  const row = profileRes.data as
    | { id?: string; is_active?: boolean; username?: string }
    | null;
  if (!row || row.is_active !== true) {
    return {
      ok: false,
      status: 403,
      code: "forbidden",
      message: "not an active account",
    };
  }
  const username = normalizeUsername(row.username);
  if (row.id !== uid || !isValidUsername(username)) {
    return {
      ok: false,
      status: 500,
      code: "server_error",
      message: "authorization check failed",
    };
  }
  return { ok: true, uid, username };
}

export type ReauthenticateResult =
  | "success"
  | "invalidCredentials"
  | "serverError";

/**
 * Verify the caller's CURRENT password without disturbing their live session, by
 * signing in on an ISOLATED anon client (its own in-memory, non-persisted
 * session). Only Auth's explicit invalid_credentials response means the password
 * is wrong. Thrown/network/rate-limit/unexpected responses fail as server errors.
 * Never logs the email/password or raw SDK errors.
 */
export async function reauthenticate(
  anonClient: SupabaseClient,
  internalEmail: string,
  currentPassword: string,
): Promise<ReauthenticateResult> {
  try {
    res = await anonClient.auth.signInWithPassword({
      email: internalEmail,
      password: currentPassword,
    });
    if (res.error) {
      return res.error.code === "invalid_credentials"
        ? "invalidCredentials"
        : "serverError";
    }
    return res.data?.session ? "success" : "serverError";
  } catch {
    return "serverError";
  }
  // No error but no session is unexpected — fail closed (not "wrong password").
  return res.data?.session ? "success" : "serverError";
}

/**
 * Update ONLY the caller's Auth password, then finalize via the service-only RPC.
 * Extracted so the ordering / partial-failure behavior is unit-testable with a
 * fake client. Order (no distributed txn): Auth update → finalize RPC → return.
 */
export async function performOwnPasswordChange(
  serviceClient: SupabaseClient,
  uid: string,
  newPassword: string,
): Promise<Response> {
  // 1) Update the caller's own Auth password (service_role). Sessions are not
  //    revoked here.
  let updated;
  try {
    updated = await serviceClient.auth.admin.updateUserById(uid, {
      password: newPassword,
    });
  } catch {
    console.error("change-own-password: auth.updateUserById threw");
    // Auth update did not return success → never call the finalization RPC.
    return errorResponse("server_error", "could not change the password", 500);
  }
  if (updated.error || !updated.data?.user) {
    console.error("change-own-password: auth.updateUserById failed");
    // Auth update FAILED → the RPC is NOT called; nothing to clean up.
    return errorResponse("server_error", "could not change the password", 500);
  }

  // 2) Finalize: clear must_change_password + audit, atomically, via the
  //    service-only RPC (which independently re-validates the caller).
  let rpc;
  try {
    rpc = await serviceClient.rpc("record_own_password_change", {
      p_user_id: uid,
    });
  } catch {
    console.error(
      "change-own-password: record_own_password_change threw after Auth update",
    );
    return errorResponse(
      "server_error",
      "password change could not be completed",
      500,
    );
  }
  if (rpc.error) {
    console.error(
      "change-own-password: record_own_password_change failed after Auth update",
    );
    return errorResponse(
      "server_error",
      "password change could not be completed",
      500,
    );
  }

  // 3) Success — safe summary only. No password/email/token.
  return json({ user: rpc.data }, 200);
}

interface ClientOptions {
  global?: { headers?: Record<string, string> };
  auth?: { autoRefreshToken?: boolean; persistSession?: boolean };
}
type ClientFactory = (
  url: string,
  key: string,
  options: ClientOptions,
) => SupabaseClient;
const defaultClientFactory: ClientFactory = (url, key, options) =>
  createClient(url, key, options);

export async function handleRequest(
  req: Request,
  clientFactory: ClientFactory = defaultClientFactory,
): Promise<Response> {
  if (req.method !== "POST") {
    return errorResponse("method_not_allowed", "use POST", 405, {
      "Allow": "POST",
    });
  }
  if (!isJsonContentType(req.headers.get("content-type"))) {
    return errorResponse(
      "unsupported_media_type",
      "Content-Type must be application/json",
      415,
    );
  }
  const auth = req.headers.get("authorization") ?? "";
  if (!/^Bearer\s+.+/i.test(auth)) {
    return errorResponse("unauthenticated", "missing bearer token", 401);
  }

  const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
  const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY");
  const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!SUPABASE_URL || !SUPABASE_ANON_KEY || !SUPABASE_SERVICE_ROLE_KEY) {
    console.error(
      "change-own-password: missing required environment configuration",
    );
    return errorResponse("server_error", "server is not configured", 500);
  }

  const bounded = await readBoundedBody(
    req.body,
    req.headers.get("content-length"),
    MAX_BODY_BYTES,
  );
  if (!bounded.ok) {
    return errorResponse("payload_too_large", "request body too large", 413);
  }
  let parsed: unknown;
  try {
    parsed = JSON.parse(
      new TextDecoder("utf-8", { fatal: true }).decode(bounded.bytes),
    );
  } catch {
    return errorResponse("invalid_request", "malformed JSON body", 400);
  }

  // Structural body validation (strict allowlist), then the new-password policy,
  // then the differ-from-current rule — all BEFORE any network client is built.
  const input = validatePasswordChangeInput(parsed);
  if (!input.ok) return errorResponse("invalid_request", input.error, 400);
  const { currentPassword, newPassword } = input.value;

  const policy = validateNewPassword(newPassword);
  if (!policy.ok) {
    return errorResponse("weak_password", policy.error, 400);
  }
  if (newPassword === currentPassword) {
    return errorResponse(
      "invalid_request",
      "new_password must differ from current_password",
      400,
    );
  }

  // Caller-scoped client (RLS) for authentication + authorization.
  const userClient = clientFactory(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: auth } },
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const authz = await authorizeActiveStaff(userClient);
  if (!authz.ok) return errorResponse(authz.code, authz.message, authz.status);
  const uid = authz.uid;

  // Derive the hidden internal email in-function (never accepted/returned/logged).
  const internalEmail = buildInternalEmail(authz.username);

  // Re-authenticate the CURRENT password on an isolated anon client (its own
  // in-memory session; the caller's live session is untouched, none revoked).
  const reauthClient = clientFactory(SUPABASE_URL, SUPABASE_ANON_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const reauthResult = await reauthenticate(
    reauthClient,
    internalEmail,
    currentPassword,
  );
  if (reauthResult === "invalidCredentials") {
    return errorResponse(
      "invalid_credentials",
      "current password is incorrect",
      401,
    );
  }
  if (reauthResult === "serverError") {
    return errorResponse(
      "server_error",
      "current password could not be verified",
      500,
    );
  }

  // Service client — built ONLY after caller auth + re-auth + validation succeed.
  const serviceClient = clientFactory(
    SUPABASE_URL,
    SUPABASE_SERVICE_ROLE_KEY,
    {
      auth: { autoRefreshToken: false, persistSession: false },
    },
  );

  return await performOwnPasswordChange(serviceClient, uid, newPassword);
}

// Start the server only when run as the entry point — so tests can import the
// exported handler/units without binding a port.
if (import.meta.main) {
  Deno.serve((req) => handleRequest(req));
}
