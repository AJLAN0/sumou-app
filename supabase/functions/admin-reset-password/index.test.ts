// Unit tests for the admin-reset-password Edge Function, using hand-rolled fake
// Supabase clients (no running stack). Importing index.ts does NOT start a server
// (Deno.serve is guarded by import.meta.main).
//
// Structural input validation (unknown fields, invalid UUID, forbidden keys) lives
// in `validateResetPasswordInput` and is covered in ../_shared/auth-utils.test.ts.
// Effective-permission math lives in `public.has_feature` (DB QA). These tests
// cover: caller authorization (admin + can_manage_users, NOT can_manage_permissions;
// fail-closed reads), request framing, and the Auth→DB ordering / partial-failure
// behavior of performReset.
import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  authorizeAdminReset,
  callerHasFeature,
  handleRequest,
  performReset,
} from "./index.ts";

// Env is read by handleRequest AFTER method/content-type/bearer checks; set dummy
// values so the "malformed JSON" path (which returns before any network client is
// built) is reachable. Never real secrets.
Deno.env.set("SUPABASE_URL", "http://localhost");
Deno.env.set("SUPABASE_ANON_KEY", "anon-test-key");
Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "service-test-key");

type QueryResult = { data: unknown; error: unknown };
type Canned = (
  table: string,
  filters: Record<string, unknown>,
  kind: "single" | "list",
) => QueryResult;
type Rpc = (name: string, args: Record<string, unknown>) => QueryResult;

// ---- fake caller-scoped (RLS) client for authorizeAdminReset -----------------
// deno-lint-ignore no-explicit-any
function fakeUserClient(getUser: QueryResult, canned: Canned, rpc: Rpc): any {
  const from = (table: string) => {
    const filters: Record<string, unknown> = {};
    const builder = {
      select: () => builder,
      eq: (k: string, v: unknown) => {
        filters[k] = v;
        return builder;
      },
      maybeSingle: () => Promise.resolve(canned(table, filters, "single")),
      then: (res: (r: QueryResult) => unknown, rej?: (e: unknown) => unknown) =>
        Promise.resolve(canned(table, filters, "list")).then(res, rej),
    };
    return builder;
  };
  return {
    auth: { getUser: () => Promise.resolve(getUser) },
    from,
    rpc: (name: string, args: Record<string, unknown>) =>
      Promise.resolve(rpc(name, args)),
  };
}

const OK_USER: QueryResult = { data: { user: { id: "u1" } }, error: null };
const ADMIN_ROLES: QueryResult = {
  data: [{ roles: { code: "admin", is_active: true } }],
  error: null,
};
const ACTIVE_PROFILE: QueryResult = {
  data: { id: "u1", is_active: true },
  error: null,
};

const adminTables: Canned = (table) => {
  if (table === "profiles") return ACTIVE_PROFILE;
  if (table === "user_roles") return ADMIN_ROLES;
  return { data: null, error: null };
};

function hasFeatureRpc(grants: Record<string, boolean>): Rpc {
  return (name, args) => {
    if (name !== "has_feature") return { data: null, error: null };
    const code = String(args["perm_code"] ?? "");
    return { data: grants[code] === true, error: null };
  };
}

// ---- callerHasFeature: RPC-result mapping ------------------------------------

Deno.test("callerHasFeature: has_feature true → granted", async () => {
  const c = fakeUserClient(
    OK_USER,
    adminTables,
    hasFeatureRpc({ can_x: true }),
  );
  const r = await callerHasFeature(c, "can_x");
  assert(r.ok && r.granted === true);
});

Deno.test("callerHasFeature: has_feature false → denied", async () => {
  const c = fakeUserClient(
    OK_USER,
    adminTables,
    hasFeatureRpc({ can_x: false }),
  );
  const r = await callerHasFeature(c, "can_x");
  assert(r.ok && r.granted === false);
});

Deno.test("callerHasFeature: RPC error fails closed", async () => {
  const c = fakeUserClient(OK_USER, adminTables, () => ({
    data: null,
    error: { message: "boom" },
  }));
  const r = await callerHasFeature(c, "can_x");
  assertEquals(r.ok, false);
});

// ---- authorizeAdminReset: admin + can_manage_users ONLY ----------------------

Deno.test("authorizeAdminReset: admin + can_manage_users → ok (does NOT require can_manage_permissions)", async () => {
  // can_manage_permissions is explicitly false → still authorized.
  const c = fakeUserClient(
    OK_USER,
    adminTables,
    hasFeatureRpc({ can_manage_users: true, can_manage_permissions: false }),
  );
  const r = await authorizeAdminReset(c);
  assert(r.ok && r.uid === "u1");
});

Deno.test("authorizeAdminReset: missing can_manage_users → 403", async () => {
  const c = fakeUserClient(
    OK_USER,
    adminTables,
    hasFeatureRpc({ can_manage_users: false, can_manage_permissions: true }),
  );
  const r = await authorizeAdminReset(c);
  assert(!r.ok);
  if (!r.ok) {
    assertEquals(r.status, 403);
    assert(r.message.includes("can_manage_users"));
  }
});

Deno.test("authorizeAdminReset: has_feature RPC error → 500 (fail closed)", async () => {
  const rpc: Rpc = (name) =>
    name === "has_feature"
      ? { data: null, error: { message: "rpc down" } }
      : { data: null, error: null };
  const r = await authorizeAdminReset(
    fakeUserClient(OK_USER, adminTables, rpc),
  );
  assert(!r.ok);
  if (!r.ok) assertEquals(r.status, 500);
});

Deno.test("authorizeAdminReset: profile query error → 500 (fail closed)", async () => {
  const canned: Canned = (table) =>
    table === "profiles"
      ? { data: null, error: { message: "db down" } }
      : { data: null, error: null };
  const r = await authorizeAdminReset(
    fakeUserClient(OK_USER, canned, hasFeatureRpc({})),
  );
  assert(!r.ok);
  if (!r.ok) assertEquals(r.status, 500);
});

Deno.test("authorizeAdminReset: user_roles query error → 500 (fail closed)", async () => {
  const canned: Canned = (table) => {
    if (table === "profiles") return ACTIVE_PROFILE;
    if (table === "user_roles") {
      return { data: null, error: { message: "db down" } };
    }
    return { data: null, error: null };
  };
  const r = await authorizeAdminReset(
    fakeUserClient(OK_USER, canned, hasFeatureRpc({})),
  );
  assert(!r.ok);
  if (!r.ok) assertEquals(r.status, 500);
});

Deno.test("authorizeAdminReset: inactive/soft-deleted caller (no row) → 403", async () => {
  const canned: Canned = (table) =>
    table === "profiles"
      ? { data: null, error: null }
      : { data: null, error: null };
  const r = await authorizeAdminReset(
    fakeUserClient(OK_USER, canned, hasFeatureRpc({})),
  );
  assert(!r.ok);
  if (!r.ok) assertEquals(r.status, 403);
});

Deno.test("authorizeAdminReset: non-admin caller → 403", async () => {
  const canned: Canned = (table) => {
    if (table === "profiles") return ACTIVE_PROFILE;
    if (table === "user_roles") {
      return {
        data: [{ roles: { code: "manager", is_active: true } }],
        error: null,
      };
    }
    return { data: null, error: null };
  };
  const r = await authorizeAdminReset(
    fakeUserClient(OK_USER, canned, hasFeatureRpc({ can_manage_users: true })),
  );
  assert(!r.ok);
  if (!r.ok) assertEquals(r.status, 403);
});

Deno.test("authorizeAdminReset: unauthenticated → 401", async () => {
  const c = fakeUserClient(
    { data: { user: null }, error: null },
    adminTables,
    hasFeatureRpc({}),
  );
  const r = await authorizeAdminReset(c);
  assert(!r.ok);
  if (!r.ok) assertEquals(r.status, 401);
});

// ---- performReset: ordering / partial-failure --------------------------------

type UpdateResult = { data: unknown; error: unknown };
function fakeService(opts: {
  target?: QueryResult;
  updateResult?: UpdateResult;
  rpcResult?: QueryResult;
}) {
  const calls: string[] = [];
  const updateArgs: { id?: string; password?: string } = {};
  const rpcArgs: Record<string, unknown> = {};
  // deno-lint-ignore no-explicit-any
  const client: any = {
    from: (_table: string) => ({
      select: () => ({
        eq: () => ({
          maybeSingle: () => {
            calls.push("preflight");
            return Promise.resolve(opts.target ?? { data: null, error: null });
          },
        }),
      }),
    }),
    auth: {
      admin: {
        updateUserById: (id: string, o: { password: string }) => {
          calls.push("update");
          updateArgs.id = id;
          updateArgs.password = o.password;
          return Promise.resolve(
            opts.updateResult ?? { data: { user: { id } }, error: null },
          );
        },
      },
    },
    rpc: (name: string, args: Record<string, unknown>) => {
      calls.push("rpc:" + name);
      Object.assign(rpcArgs, args);
      return Promise.resolve(
        opts.rpcResult ??
          {
            data: { id: "t1", must_change_password: true, is_active: true },
            error: null,
          },
      );
    },
  };
  return { client, calls, updateArgs, rpcArgs };
}

const TARGET = "11111111-1111-1111-1111-111111111111";

Deno.test("performReset: success → 200, temp password once, order preflight→update→rpc", async () => {
  const f = fakeService({
    target: {
      data: { id: TARGET, is_active: true, deleted_at: null },
      error: null,
    },
  });
  const res = await performReset(
    f.client,
    "actor-1",
    TARGET,
    () => "FIXED_TEMP_1",
  );
  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.temp_password, "FIXED_TEMP_1");
  // Auth update targeted the validated UUID with the generated temp password.
  assertEquals(f.updateArgs.id, TARGET);
  assertEquals(f.updateArgs.password, "FIXED_TEMP_1");
  // RPC ran AFTER the Auth update, with the right actor + target.
  assertEquals(f.calls, [
    "preflight",
    "update",
    "rpc:record_admin_password_reset",
  ]);
  assertEquals(f.rpcArgs.p_actor_id, "actor-1");
  assertEquals(f.rpcArgs.p_target_user_id, TARGET);
  // no-store headers present.
  assertEquals(res.headers.get("Cache-Control"), "no-store, max-age=0");
  // returned user is the safe RPC summary; no internal email leaks.
  assert(!("email" in body.user));
});

Deno.test("performReset: inactive target allowed (proceeds; not reactivated here)", async () => {
  const f = fakeService({
    target: {
      data: { id: TARGET, is_active: false, deleted_at: null },
      error: null,
    },
    rpcResult: {
      data: { id: TARGET, must_change_password: true, is_active: false },
      error: null,
    },
  });
  const res = await performReset(f.client, "actor-1", TARGET, () => "T");
  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.user.is_active, false); // NOT reactivated
  assert(f.calls.includes("update"));
});

Deno.test("performReset: self-reset (actor === target) allowed", async () => {
  const f = fakeService({
    target: {
      data: { id: TARGET, is_active: true, deleted_at: null },
      error: null,
    },
  });
  const res = await performReset(f.client, TARGET, TARGET, () => "T");
  assertEquals(res.status, 200);
  assertEquals(f.rpcArgs.p_actor_id, TARGET);
  assertEquals(f.rpcArgs.p_target_user_id, TARGET);
});

Deno.test("performReset: missing target → 404, no Auth update, no RPC", async () => {
  const f = fakeService({ target: { data: null, error: null } });
  const res = await performReset(f.client, "actor-1", TARGET, () => "T");
  assertEquals(res.status, 404);
  assert(!f.calls.includes("update"));
  assert(!f.calls.some((c) => c.startsWith("rpc:")));
});

Deno.test("performReset: soft-deleted target → 404, no Auth update", async () => {
  const f = fakeService({
    target: {
      data: { id: TARGET, is_active: true, deleted_at: "2020-01-01T00:00:00Z" },
      error: null,
    },
  });
  const res = await performReset(f.client, "actor-1", TARGET, () => "T");
  assertEquals(res.status, 404);
  assert(!f.calls.includes("update"));
});

Deno.test("performReset: preflight query error → 500 (fail closed), no Auth update", async () => {
  const f = fakeService({
    target: { data: null, error: { message: "db down" } },
  });
  const res = await performReset(f.client, "actor-1", TARGET, () => "T");
  assertEquals(res.status, 500);
  assert(!f.calls.includes("update"));
});

Deno.test("performReset: Auth update fails → 500, RPC NOT called, no temp password", async () => {
  const f = fakeService({
    target: {
      data: { id: TARGET, is_active: true, deleted_at: null },
      error: null,
    },
    updateResult: { data: null, error: { message: "auth down" } },
  });
  const res = await performReset(f.client, "actor-1", TARGET, () => "SECRET");
  assertEquals(res.status, 500);
  assert(!f.calls.some((c) => c.startsWith("rpc:"))); // DB flag RPC never runs
  const body = await res.json();
  assert(!("temp_password" in body));
});

Deno.test("performReset: RPC fails after Auth update → 500, temp password NOT returned", async () => {
  const f = fakeService({
    target: {
      data: { id: TARGET, is_active: true, deleted_at: null },
      error: null,
    },
    rpcResult: { data: null, error: { message: "flag failed" } },
  });
  const res = await performReset(f.client, "actor-1", TARGET, () => "SECRET");
  assertEquals(res.status, 500);
  // Auth was updated, then RPC ran and failed — order proves the sequence.
  assertEquals(f.calls, [
    "preflight",
    "update",
    "rpc:record_admin_password_reset",
  ]);
  const body = await res.json();
  assert(!("temp_password" in body)); // never expose a non-finalized reset
});

// ---- handleRequest: request framing (no network before these returns) --------

Deno.test("handleRequest: GET → 405 + Allow: POST", async () => {
  const res = await handleRequest(new Request("http://x", { method: "GET" }));
  assertEquals(res.status, 405);
  assertEquals(res.headers.get("Allow"), "POST");
});

Deno.test("handleRequest: PUT → 405", async () => {
  const res = await handleRequest(new Request("http://x", { method: "PUT" }));
  assertEquals(res.status, 405);
});

Deno.test("handleRequest: wrong Content-Type → 415", async () => {
  const res = await handleRequest(
    new Request("http://x", {
      method: "POST",
      headers: { "content-type": "text/plain" },
      body: "x",
    }),
  );
  assertEquals(res.status, 415);
});

Deno.test("handleRequest: missing bearer → 401", async () => {
  const res = await handleRequest(
    new Request("http://x", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: "{}",
    }),
  );
  assertEquals(res.status, 401);
});

Deno.test("handleRequest: malformed JSON → 400 (returns before any network client)", async () => {
  const res = await handleRequest(
    new Request("http://x", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "authorization": "Bearer abc.def.ghi",
      },
      body: "{",
    }),
  );
  assertEquals(res.status, 400);
  const body = await res.json();
  assertEquals(body.error.code, "invalid_request");
});
