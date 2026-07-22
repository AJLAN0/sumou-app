// admin-create-user — Supabase Edge Function (Sprint 10 Step 10.2).
//
// Admin-only user provisioning. Flow:
//   authenticate caller (JWT) → authorize (active admin + can_manage_users, from
//   the DB) → validate/normalize input → generate a secure temp password →
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

import { createClient, type SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  buildInternalEmail,
  generateTempPassword,
  MAX_BODY_BYTES,
  validateCreateUserInput,
} from "../_shared/auth-utils.ts";

const JSON_HEADERS = { "Content-Type": "application/json" };

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), { status, headers: JSON_HEADERS });
}
function errorResponse(code: string, message: string, status: number): Response {
  return json({ error: { code, message } }, status);
}

/** Effective can_manage_users for the caller, via their own RLS-scoped reads. */
async function callerCanManageUsers(userClient: SupabaseClient, uid: string): Promise<boolean> {
  const { data: override } = await userClient
    .from("user_permissions")
    .select("granted, permissions!inner(code, is_active)")
    .eq("user_id", uid)
    .eq("permissions.code", "can_manage_users")
    .eq("permissions.is_active", true)
    .maybeSingle();
  if (override) return override.granted === true;

  const { data: defaults } = await userClient
    .from("role_permissions")
    .select("granted, permissions!inner(code, is_active)")
    .eq("permissions.code", "can_manage_users")
    .eq("permissions.is_active", true);
  return (defaults ?? []).some((r: { granted: boolean }) => r.granted === true);
}

/** Authorize: authenticated + active profile + active admin role + can_manage_users. */
async function authorizeAdmin(
  userClient: SupabaseClient,
): Promise<{ ok: true; uid: string } | { ok: false; status: number; code: string; message: string }> {
  const { data: userData, error: userErr } = await userClient.auth.getUser();
  if (userErr || !userData?.user) {
    return { ok: false, status: 401, code: "unauthenticated", message: "invalid or missing session" };
  }
  const uid = userData.user.id;

  // profiles self-read policy only returns the row when active + not soft-deleted.
  const { data: profile } = await userClient
    .from("profiles").select("id, is_active").eq("id", uid).maybeSingle();
  if (!profile || profile.is_active !== true) {
    return { ok: false, status: 403, code: "forbidden", message: "not an active account" };
  }

  const { data: roles } = await userClient
    .from("user_roles").select("roles!inner(code, is_active)").eq("user_id", uid);
  const isAdmin = (roles ?? []).some(
    (r: { roles: { code: string; is_active: boolean } }) => r.roles.code === "admin" && r.roles.is_active,
  );
  if (!isAdmin) return { ok: false, status: 403, code: "forbidden", message: "admin role required" };

  if (!(await callerCanManageUsers(userClient, uid))) {
    return { ok: false, status: 403, code: "forbidden", message: "can_manage_users required" };
  }
  return { ok: true, uid };
}

/** Map a create_staff_profile / Postgres error to a safe HTTP status (no raw leak). */
function statusForRpcError(code: string | undefined): number {
  switch (code) {
    case "23505": return 409; // unique_violation (username/profile already exists)
    case "42501": return 403; // insufficient_privilege (actor re-check failed)
    case "22023": return 400; // invalid_parameter_value
    case "P0002": return 400; // no auth user / not found
    default: return 500;
  }
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204 });
  if (req.method !== "POST") return errorResponse("method_not_allowed", "use POST", 405);

  const ctype = req.headers.get("content-type") ?? "";
  if (!ctype.toLowerCase().includes("application/json")) {
    return errorResponse("unsupported_media_type", "Content-Type must be application/json", 415);
  }

  const auth = req.headers.get("authorization") ?? "";
  if (!/^Bearer\s+.+/i.test(auth)) {
    return errorResponse("unauthenticated", "missing bearer token", 401);
  }

  const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
  const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY");
  const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!SUPABASE_URL || !SUPABASE_ANON_KEY || !SUPABASE_SERVICE_ROLE_KEY) {
    console.error("admin-create-user: missing required environment configuration");
    return errorResponse("server_error", "server is not configured", 500);
  }

  // Read the body with a size cap.
  const raw = await req.text();
  if (raw.length > MAX_BODY_BYTES) {
    return errorResponse("payload_too_large", "request body too large", 413);
  }
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    return errorResponse("invalid_request", "malformed JSON body", 400);
  }

  const validation = validateCreateUserInput(parsed);
  if (!validation.ok) return errorResponse("invalid_request", validation.error, 400);
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
  const { data: taken } = await serviceClient
    .from("profiles").select("id").eq("username", input.username).maybeSingle();
  if (taken) return errorResponse("conflict", "username is already taken", 409);

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
    return errorResponse("server_error", "could not provision the account", 500);
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
    console.error("admin-create-user: create_staff_profile failed; compensation ran");
    if (cleanup.error) {
      // Orphaned Auth user — surface a generic failure; never leak details.
      return errorResponse("server_error", "provisioning failed and cleanup did not complete", 500);
    }
    return errorResponse("provisioning_failed", "could not create the profile", statusForRpcError(rpc.error.code));
  }

  // 4) Success — return the profile + the temp password ONCE. No internal email.
  return json({ user: rpc.data, temp_password: tempPassword }, 201);
});
