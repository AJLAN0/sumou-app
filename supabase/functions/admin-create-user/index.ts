// admin-create-user — Supabase Edge Function (Sprint 10 Step 10.2).
//
// Admin-only user provisioning. Flow:
//   authenticate caller (JWT) → authorize (active admin + BOTH can_manage_users
//   AND can_manage_permissions, resolved via the authenticated has_feature RPC) →
//   validate/normalize input → generate a secure temp password →
//   create the Auth user (service_role) → call create_staff_profile RPC
//   (atomic public rows + audit) → return the temp password ONCE. If the RPC
//   fails, COMPENSATE by deleting the just-created Auth user (Auth + public schema
//   cannot share one SQL transaction). No email/notification/password delivery.
//
// Secrets come only from Deno env. Nothing hardcoded. The internal Auth email is
// built here, never accepted from the client, never returned or logged; request
// bodies and temp passwords are never logged.
//
// NOT deployed by this step — the owner deploys to DEV manually.

import {
  createClient,
  type SupabaseClient,
} from "https://esm.sh/@supabase/supabase-js@2.45.4";
import {
  buildInternalEmail,
  generateTempPassword,
  isJsonContentType,
  MAX_BODY_BYTES,
  readBoundedBody,
  validateCreateUserInput,
} from "../_shared/auth-utils.ts";

// Every response carries these. The 201 success body contains a one-time temp
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
 * `auth.uid()` and enforces everything correctly: an active/non-deleted caller,
 * explicit `user_permissions` override first (grant OR revoke), else the OR of
 * `role_permissions` defaults ACROSS THE CALLER'S OWN ACTIVE ROLES ONLY, only
 * ACTIVE permission-catalog rows participating, otherwise false.
 *
 * This must NOT be re-implemented here by reading tables directly: an active
 * admin can (by oversight RLS) read ALL `role_permissions` rows, so a code-only
 * `role_permissions` scan would count a grant belonging to an unrelated role and
 * wrongly authorize the caller. The service_role client is NEVER used for caller
 * authorization — only this authenticated `userClient`.
 *
 * Returns `{ ok: false }` on ANY RPC error (fail closed → caller 500). A clean
 * `data === true` grants; every other successful result denies (caller 403).
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
 * Authorize: authenticated + active profile + active admin role + BOTH
 * can_manage_users AND can_manage_permissions (owner-frozen create rule). Every
 * DB read fails closed: a query error → 500 (auth-check failure), never treated
 * as empty. HTTP-body roles/permissions are never consulted for authorization.
 */
export async function authorizeAdmin(
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
  // array depending on version; normalize to an array before matching so the
  // active-admin check is correct either way.
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

  for (const code of ["can_manage_users", "can_manage_permissions"]) {
    const feat = await callerHasFeature(userClient, code);
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
        message: `${code} required`,
      };
    }
  }
  return { ok: true, uid };
}

/** Map a create_staff_profile / Postgres error to a safe HTTP status (no raw leak). */
function statusForRpcError(code: string | undefined): number {
  switch (code) {
    case "23505":
      return 409; // unique_violation (username/profile already exists)
    case "42501":
      return 403; // insufficient_privilege (actor re-check failed)
    case "22023":
      return 400; // invalid_parameter_value
    case "P0002":
      return 400; // no auth user / not found
    default:
      return 500;
  }
}

export async function handleRequest(req: Request): Promise<Response> {
  // No wildcard CORS / OPTIONS preflight is offered (no approved browser-origin
  // policy). Any non-POST — including OPTIONS — gets 405 with an Allow header.
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
      "admin-create-user: missing required environment configuration",
    );
    return errorResponse("server_error", "server is not configured", 500);
  }

  // Bounded, streaming body read — never buffers an oversized request. Counts
  // actual bytes (not JS chars) and decodes UTF-8 only after the cap holds.
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

  const validation = validateCreateUserInput(parsed);
  if (!validation.ok) {
    return errorResponse("invalid_request", validation.error, 400);
  }
  const input = validation.value;

  // Caller-scoped client (RLS) for authentication + authorization.
  const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: auth } },
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const authz = await authorizeAdmin(userClient);
  if (!authz.ok) return errorResponse(authz.code, authz.message, authz.status);
  const actorId = authz.uid;

  // Service client — used ONLY after authorization succeeds.
  const serviceClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  // Friendly pre-check for a taken username (race still guarded by DB/Auth).
  // A query error fails closed (500) rather than proceeding as "not taken".
  const takenRes = await serviceClient
    .from("profiles").select("id").eq("username", input.username).maybeSingle();
  if (takenRes.error) {
    console.error("admin-create-user: username pre-check failed");
    return errorResponse("server_error", "could not verify the username", 500);
  }
  if (takenRes.data) {
    return errorResponse("conflict", "username is already taken", 409);
  }

  const internalEmail = buildInternalEmail(input.username);
  const tempPassword = generateTempPassword();

  // 1) Create the Auth user.
  const created = await serviceClient.auth.admin.createUser({
    email: internalEmail,
    password: tempPassword,
    email_confirm: true,
    user_metadata: { username: input.username },
  });
  if (created.error || !created.data?.user) {
    const msg = created.error?.message ?? "";
    // duplicate internal identity → conflict; otherwise generic.
    if (/already|exists|registered|duplicate/i.test(msg)) {
      return errorResponse("conflict", "account already exists", 409);
    }
    console.error("admin-create-user: auth.createUser failed");
    return errorResponse(
      "server_error",
      "could not provision the account",
      500,
    );
  }
  const newUserId = created.data.user.id;

  // 2) Create the public identity rows atomically via the service-only RPC.
  const rpc = await serviceClient.rpc("create_staff_profile", {
    p_actor_id: actorId,
    p_user_id: newUserId,
    p_username: input.username,
    p_full_name: input.full_name,
    p_default_role: input.default_role,
    p_roles: input.roles,
    p_photographer_types: input.photographer_types,
    p_permission_overrides: input.permission_overrides,
  });

  if (rpc.error) {
    // 3) COMPENSATE — delete ONLY the user created in this request.
    const cleanup = await serviceClient.auth.admin.deleteUser(newUserId);
    console.error(
      "admin-create-user: create_staff_profile failed; compensation ran",
    );
    if (cleanup.error) {
      // Orphaned Auth user — surface a generic failure; never leak details.
      return errorResponse(
        "server_error",
        "provisioning failed and cleanup did not complete",
        500,
      );
    }
    return errorResponse(
      "provisioning_failed",
      "could not create the profile",
      statusForRpcError(rpc.error.code),
    );
  }

  // 4) Success — return the profile + the temp password ONCE. No internal email.
  return json({ user: rpc.data, temp_password: tempPassword }, 201);
}

// Start the server only when run as the entry point — so tests can import the
// exported handler/authorization functions without binding a port.
if (import.meta.main) {
  Deno.serve(handleRequest);
}
