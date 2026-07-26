// admin-reset-password — Supabase Edge Function (Sprint 10 Step 10.3).
//
// Admin-only password reset. Flow:
//   authenticate caller (JWT) → authorize (active admin + can_manage_users,
//   resolved via the authenticated has_feature RPC — NOT can_manage_permissions) →
//   validate input (target user_id only) → PREFLIGHT the target (exists, not
//   soft-deleted) with service_role → generate a secure temp password → update the
//   target's Auth password (service_role) → call record_admin_password_reset RPC
//   (set must_change_password=true + audit, atomically) → return the temp password
//   ONCE. No email/notification/recovery-link is sent.
//
// Auth and the public schema cannot share one SQL transaction. Ordering is
// Auth-update BEFORE the RPC, with a preflight to make the RPC's target checks
// almost never fail post-update. If the RPC still fails AFTER the Auth password
// changed, we return a GENERIC failure and do NOT expose the temp password (the
// safe recovery is to reset again — idempotent). We never restore the old password
// (it is not available) and never invent a distributed transaction.
//
// Secrets come only from Deno env. Nothing hardcoded. The internal Auth email is
// never accepted, returned, or logged; request bodies and temp passwords are never
// logged.
//
// NOT deployed by this step — the owner deploys to DEV manually.

import {
  createClient,
  type SupabaseClient,
} from "https://esm.sh/@supabase/supabase-js@2.45.4";
import {
  generateTempPassword,
  isJsonContentType,
  MAX_BODY_BYTES,
  readBoundedBody,
  validateResetPasswordInput,
} from "../_shared/auth-utils.ts";

// Every response carries these. The 200 success body contains a one-time temp
// password, so responses must NEVER be cached or content-sniffed.
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

/**
 * Fail-closed effective-permission check for the caller, delegated to the
 * canonical authenticated helper `public.has_feature(perm_code)` via the caller-
 * scoped (RLS) client. That SECURITY DEFINER function resolves the permission for
 * `auth.uid()` (active/non-deleted caller, explicit override first, else OR of the
 * caller's OWN active-role defaults, active permissions only, otherwise false).
 *
 * Never re-implemented by reading tables directly — an active admin can read ALL
 * `role_permissions` via oversight RLS, so a code-only scan could count an
 * unrelated role's grant. The service_role client is NEVER used for caller
 * authorization — only this authenticated `userClient`.
 *
 * `{ ok: false }` on ANY RPC error (fail closed → caller 500). `data === true`
 * grants; every other successful result denies (caller 403).
 */
export async function callerHasFeature(
  userClient: SupabaseClient,
  permissionCode: string,
): Promise<{ ok: true; granted: boolean } | { ok: false }> {
  const { data, error } = await userClient.rpc("has_feature", {
    perm_code: permissionCode,
  });
  if (error) return { ok: false }; // RPC failed → fail closed
  if (data === true) return { ok: true, granted: true };
  return { ok: true, granted: false };
}

/**
 * Authorize: authenticated + active profile + active admin role + effective
 * can_manage_users. Reset does NOT require can_manage_permissions (it assigns no
 * roles/permissions). Every DB read fails closed: a query error → 500, never
 * treated as empty. HTTP-body values are never consulted for authorization.
 */
export async function authorizeAdminReset(
  userClient: SupabaseClient,
): Promise<
  { ok: true; uid: string } | {
    ok: false;
    status: number;
    code: string;
    message: string;
  }
> {
  const { data: userData, error: userErr } = await userClient.auth.getUser();
  if (userErr || !userData?.user) {
    return {
      ok: false,
      status: 401,
      code: "unauthenticated",
      message: "invalid or missing session",
    };
  }
  const uid = userData.user.id;

  // profiles self-read policy only returns the row when active + not soft-deleted.
  const profileRes = await userClient
    .from("profiles").select("id, is_active").eq("id", uid).maybeSingle();
  if (profileRes.error) {
    return {
      ok: false,
      status: 500,
      code: "server_error",
      message: "authorization check failed",
    };
  }
  if (!profileRes.data || profileRes.data.is_active !== true) {
    return {
      ok: false,
      status: 403,
      code: "forbidden",
      message: "not an active account",
    };
  }

  const rolesRes = await userClient
    .from("user_roles").select("roles!inner(code, is_active)").eq(
      "user_id",
      uid,
    );
  if (rolesRes.error) {
    return {
      ok: false,
      status: 500,
      code: "server_error",
      message: "authorization check failed",
    };
  }
  // PostgREST may type/return an embedded to-one relation as an object OR an
  // array depending on version; normalize to an array before matching.
  const isAdmin = (rolesRes.data ?? []).some((r: { roles: unknown }) => {
    const roles = Array.isArray(r.roles) ? r.roles : [r.roles];
    return roles.some(
      (x: { code?: string; is_active?: boolean }) =>
        x?.code === "admin" && x?.is_active === true,
    );
  });
  if (!isAdmin) {
    return {
      ok: false,
      status: 403,
      code: "forbidden",
      message: "admin role required",
    };
  }

  const feat = await callerHasFeature(userClient, "can_manage_users");
  if (!feat.ok) {
    return {
      ok: false,
      status: 500,
      code: "server_error",
      message: "authorization check failed",
    };
  }
  if (!feat.granted) {
    return {
      ok: false,
      status: 403,
      code: "forbidden",
      message: "can_manage_users required",
    };
  }
  return { ok: true, uid };
}

/**
 * Perform the reset given an ALREADY-AUTHORIZED actor and a validated target
 * UUID, using the service-role client. Extracted so the ordering / partial-failure
 * behavior is unit-testable with a fake client. Order (no distributed txn):
 *   preflight target → generate temp → Auth update → finalize RPC → return once.
 * `makeTempPassword` is injectable only so a test can assert the temp password
 * appears ONLY in a fully-successful response.
 */
export async function performReset(
  serviceClient: SupabaseClient,
  actorId: string,
  targetUserId: string,
  makeTempPassword: () => string = generateTempPassword,
): Promise<Response> {
  // PREFLIGHT the target BEFORE any Auth change: it must exist and not be
  // soft-deleted. (profiles.id → auth.users(id) FK guarantees a matching Auth row
  // for any existing profile.) Inactive targets are allowed and NOT reactivated.
  // A query error fails closed (500). record_admin_password_reset re-checks all of
  // this too — the preflight just keeps the post-Auth RPC from failing on target
  // validity in the common case.
  const targetRes = await serviceClient
    .from("profiles")
    .select("id, is_active, deleted_at")
    .eq("id", targetUserId)
    .maybeSingle();
  if (targetRes.error) {
    console.error("admin-reset-password: target preflight failed");
    return errorResponse("server_error", "could not verify the target", 500);
  }
  if (!targetRes.data || targetRes.data.deleted_at !== null) {
    // Missing OR soft-deleted → not a resettable target. 404 (does not reveal
    // arbitrary Auth-email existence — only that this profile is not resettable).
    return errorResponse("not_found", "target user not found", 404);
  }

  const tempPassword = makeTempPassword();

  // 1) Update the target's Auth password (service_role). No email/recovery link.
  const updated = await serviceClient.auth.admin.updateUserById(targetUserId, {
    password: tempPassword,
  });
  if (updated.error || !updated.data?.user) {
    console.error("admin-reset-password: auth.updateUserById failed");
    return errorResponse("server_error", "could not reset the password", 500);
  }

  // 2) Finalize: set must_change_password=true + audit, atomically, via the
  //    service-only RPC (which independently re-checks actor + target).
  const rpc = await serviceClient.rpc("record_admin_password_reset", {
    p_actor_id: actorId,
    p_target_user_id: targetUserId,
  });

  if (rpc.error) {
    // PARTIAL FAILURE: the Auth password was already changed but the flag/audit
    // was NOT recorded. We CANNOT restore the old password (not available) and we
    // must NOT expose the temp password for a non-finalized reset. Return a
    // generic failure; the safe recovery is to reset again (idempotent — a new
    // temp password, and the flag+audit are set on success).
    console.error(
      "admin-reset-password: record_admin_password_reset failed after Auth update",
    );
    return errorResponse(
      "server_error",
      "password reset could not be completed",
      500,
    );
  }

  // 3) Success — return the safe profile summary + the temp password ONCE.
  return json({ user: rpc.data, temp_password: tempPassword }, 200);
}

export async function handleRequest(req: Request): Promise<Response> {
  // No wildcard CORS / OPTIONS preflight is offered. Any non-POST — including
  // OPTIONS — gets 405 with an Allow header.
  if (req.method !== "POST") {
    return errorResponse("method_not_allowed", "use POST", 405, {
      "Allow": "POST",
    });
  }

  // Content-Type must be EXACTLY application/json (charset param allowed).
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
      "admin-reset-password: missing required environment configuration",
    );
    return errorResponse("server_error", "server is not configured", 500);
  }

  // Bounded, streaming body read — never buffers an oversized request.
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

  const validation = validateResetPasswordInput(parsed);
  if (!validation.ok) {
    return errorResponse("invalid_request", validation.error, 400);
  }
  const targetUserId = validation.value.user_id;

  // Caller-scoped client (RLS) for authentication + authorization.
  const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: auth } },
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const authz = await authorizeAdminReset(userClient);
  if (!authz.ok) return errorResponse(authz.code, authz.message, authz.status);
  const actorId = authz.uid;

  // Service client — used ONLY after authorization succeeds.
  const serviceClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  return await performReset(serviceClient, actorId, targetUserId);
}

// Start the server only when run as the entry point — so tests can import the
// exported handler/authorization functions without binding a port.
if (import.meta.main) {
  Deno.serve(handleRequest);
}
