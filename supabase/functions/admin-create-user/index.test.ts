// Authorization unit tests for the admin-create-user Edge Function, using a hand
// -rolled fake Supabase client (no running stack). Importing index.ts does NOT
// start a server (Deno.serve is guarded by import.meta.main).
//
// callerHasFeature now delegates to the canonical authenticated RPC
// public.has_feature(perm_code); the Edge Function itself no longer computes
// override-precedence or role-default fallback. That logic lives in has_feature
// and is covered by database QA — so those old table-scan tests are gone. These
// tests only assert: the RPC result is mapped correctly, every read fails closed,
// and authorizeAdmin requires BOTH permissions.
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { authorizeAdmin, callerHasFeature } from "./index.ts";

type QueryResult = { data: unknown; error: unknown };
/** canned(table, filters, kind) → {data, error}. `kind` is "single" or "list". */
type Canned = (table: string, filters: Record<string, unknown>, kind: "single" | "list") => QueryResult;
/** rpc(name, args) → {data, error}. */
type Rpc = (name: string, args: Record<string, unknown>) => QueryResult;

// deno-lint-ignore no-explicit-any
function fakeClient(getUser: QueryResult, canned: Canned, rpc: Rpc): any {
  const from = (table: string) => {
    const filters: Record<string, unknown> = {};
    const builder = {
      select: () => builder,
      eq: (k: string, v: unknown) => {
        filters[k] = v;
        return builder;
      },
      maybeSingle: () => Promise.resolve(canned(table, filters, "single")),
      // awaiting the builder itself (the user_roles list path)
      then: (res: (r: QueryResult) => unknown, rej?: (e: unknown) => unknown) =>
        Promise.resolve(canned(table, filters, "list")).then(res, rej),
    };
    return builder;
  };
  return {
    auth: { getUser: () => Promise.resolve(getUser) },
    from,
    rpc: (name: string, args: Record<string, unknown>) => Promise.resolve(rpc(name, args)),
  };
}

const OK_USER: QueryResult = { data: { user: { id: "u1" } }, error: null };
const ADMIN_ROLES: QueryResult = { data: [{ roles: { code: "admin", is_active: true } }], error: null };
const ACTIVE_PROFILE: QueryResult = { data: { id: "u1", is_active: true }, error: null };

/** Default table responses for a healthy active admin (profiles + user_roles). */
const adminTables: Canned = (table) => {
  if (table === "profiles") return ACTIVE_PROFILE;
  if (table === "user_roles") return ADMIN_ROLES;
  return { data: null, error: null };
};

/** has_feature RPC stub: per-code boolean grant map. Unknown code → false. */
function hasFeatureRpc(grants: Record<string, boolean>): Rpc {
  return (name, args) => {
    if (name !== "has_feature") return { data: null, error: null };
    const code = String(args["perm_code"] ?? "");
    return { data: grants[code] === true, error: null };
  };
}

// ---- callerHasFeature: pure RPC-result mapping ----------------------------

Deno.test("callerHasFeature: has_feature true → granted", async () => {
  const c = fakeClient(OK_USER, adminTables, hasFeatureRpc({ can_x: true }));
  const r = await callerHasFeature(c, "can_x");
  assert(r.ok && r.granted === true);
});

Deno.test("callerHasFeature: has_feature false → denied", async () => {
  const c = fakeClient(OK_USER, adminTables, hasFeatureRpc({ can_x: false }));
  const r = await callerHasFeature(c, "can_x");
  assert(r.ok && r.granted === false);
});

Deno.test("callerHasFeature: any non-true success → denied", async () => {
  // A null/undefined/non-boolean success must NOT be treated as granted.
  const c = fakeClient(OK_USER, adminTables, () => ({ data: null, error: null }));
  const r = await callerHasFeature(c, "can_x");
  assert(r.ok && r.granted === false);
});

Deno.test("callerHasFeature: RPC error fails closed", async () => {
  const c = fakeClient(OK_USER, adminTables, () => ({ data: null, error: { message: "boom" } }));
  const r = await callerHasFeature(c, "can_x");
  assertEquals(r.ok, false);
});

// ---- authorizeAdmin: requires BOTH permissions ----------------------------

Deno.test("authorizeAdmin: both permissions true → ok", async () => {
  const c = fakeClient(
    OK_USER,
    adminTables,
    hasFeatureRpc({ can_manage_users: true, can_manage_permissions: true }),
  );
  const r = await authorizeAdmin(c);
  assert(r.ok && r.uid === "u1");
});

Deno.test("authorizeAdmin: requires BOTH — missing can_manage_permissions → 403", async () => {
  const c = fakeClient(
    OK_USER,
    adminTables,
    hasFeatureRpc({ can_manage_users: true, can_manage_permissions: false }),
  );
  const r = await authorizeAdmin(c);
  assert(!r.ok);
  if (!r.ok) {
    assertEquals(r.status, 403);
    assert(r.message.includes("can_manage_permissions"));
  }
});

Deno.test("authorizeAdmin: missing can_manage_users → 403", async () => {
  const c = fakeClient(
    OK_USER,
    adminTables,
    hasFeatureRpc({ can_manage_users: false, can_manage_permissions: true }),
  );
  const r = await authorizeAdmin(c);
  assert(!r.ok);
  if (!r.ok) {
    assertEquals(r.status, 403);
    assert(r.message.includes("can_manage_users"));
  }
});

// ---- authorizeAdmin: every read fails closed ------------------------------

Deno.test("authorizeAdmin: has_feature RPC error → 500 (fail closed)", async () => {
  const rpc: Rpc = (name) => name === "has_feature"
    ? { data: null, error: { message: "rpc down" } }
    : { data: null, error: null };
  const r = await authorizeAdmin(fakeClient(OK_USER, adminTables, rpc));
  assert(!r.ok);
  if (!r.ok) assertEquals(r.status, 500);
});

Deno.test("authorizeAdmin: profile query error → 500 (fail closed)", async () => {
  const canned: Canned = (table) => {
    if (table === "profiles") return { data: null, error: { message: "db down" } };
    return { data: null, error: null };
  };
  const r = await authorizeAdmin(fakeClient(OK_USER, canned, hasFeatureRpc({})));
  assert(!r.ok);
  if (!r.ok) assertEquals(r.status, 500);
});

Deno.test("authorizeAdmin: user_roles query error → 500 (fail closed)", async () => {
  const canned: Canned = (table) => {
    if (table === "profiles") return ACTIVE_PROFILE;
    if (table === "user_roles") return { data: null, error: { message: "db down" } };
    return { data: null, error: null };
  };
  const r = await authorizeAdmin(fakeClient(OK_USER, canned, hasFeatureRpc({})));
  assert(!r.ok);
  if (!r.ok) assertEquals(r.status, 500);
});

Deno.test("authorizeAdmin: inactive/soft-deleted profile (no row) → 403", async () => {
  const canned: Canned = (table) => {
    if (table === "profiles") return { data: null, error: null }; // RLS returns no row
    return { data: null, error: null };
  };
  const r = await authorizeAdmin(fakeClient(OK_USER, canned, hasFeatureRpc({})));
  assert(!r.ok);
  if (!r.ok) assertEquals(r.status, 403);
});

Deno.test("authorizeAdmin: non-admin → 403", async () => {
  const canned: Canned = (table) => {
    if (table === "profiles") return ACTIVE_PROFILE;
    if (table === "user_roles") return { data: [{ roles: { code: "manager", is_active: true } }], error: null };
    return { data: null, error: null };
  };
  const r = await authorizeAdmin(fakeClient(OK_USER, canned, hasFeatureRpc({})));
  assert(!r.ok);
  if (!r.ok) assertEquals(r.status, 403);
});

Deno.test("authorizeAdmin: unauthenticated → 401", async () => {
  const c = fakeClient({ data: { user: null }, error: null }, adminTables, hasFeatureRpc({}));
  const r = await authorizeAdmin(c);
  assert(!r.ok);
  if (!r.ok) assertEquals(r.status, 401);
});
