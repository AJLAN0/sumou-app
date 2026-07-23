// Authorization unit tests for the admin-create-user Edge Function, using a hand
// -rolled fake Supabase client (no running stack). Importing index.ts does NOT
// start a server (Deno.serve is guarded by import.meta.main).
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { authorizeAdmin, callerHasFeature } from "./index.ts";

type QueryResult = { data: unknown; error: unknown };
/** canned(table, filters, kind) → {data, error}. `kind` is "single" or "list". */
type Canned = (table: string, filters: Record<string, unknown>, kind: "single" | "list") => QueryResult;

// deno-lint-ignore no-explicit-any
function fakeClient(getUser: QueryResult, canned: Canned): any {
  const from = (table: string) => {
    const filters: Record<string, unknown> = {};
    const builder = {
      select: () => builder,
      eq: (k: string, v: unknown) => {
        filters[k] = v;
        return builder;
      },
      maybeSingle: () => Promise.resolve(canned(table, filters, "single")),
      // awaiting the builder itself (the role_permissions list path)
      then: (res: (r: QueryResult) => unknown, rej?: (e: unknown) => unknown) =>
        Promise.resolve(canned(table, filters, "list")).then(res, rej),
    };
    return builder;
  };
  return { auth: { getUser: () => Promise.resolve(getUser) }, from };
}

const OK_USER: QueryResult = { data: { user: { id: "u1" } }, error: null };
const ADMIN_ROLES: QueryResult = { data: [{ roles: { code: "admin", is_active: true } }], error: null };
const ACTIVE_PROFILE: QueryResult = { data: { id: "u1", is_active: true }, error: null };

/** permission resolver: per-code override + default granted maps. */
function perms(
  override: Record<string, boolean | undefined>,
  defaults: Record<string, boolean>,
): Canned {
  return (table, filters, kind) => {
    const code = String(filters["permissions.code"] ?? "");
    if (table === "profiles") return ACTIVE_PROFILE;
    if (table === "user_roles") return ADMIN_ROLES;
    if (table === "user_permissions" && kind === "single") {
      const ov = override[code];
      return { data: ov === undefined ? null : { granted: ov }, error: null };
    }
    if (table === "role_permissions" && kind === "list") {
      return { data: defaults[code] ? [{ granted: true }] : [], error: null };
    }
    return { data: null, error: null };
  };
}

Deno.test("callerHasFeature: explicit override true wins over false default", async () => {
  const c = fakeClient(OK_USER, perms({ can_x: true }, { can_x: false }));
  const r = await callerHasFeature(c, "u1", "can_x");
  assert(r.ok && r.granted === true);
});

Deno.test("callerHasFeature: explicit override false wins over true default", async () => {
  const c = fakeClient(OK_USER, perms({ can_x: false }, { can_x: true }));
  const r = await callerHasFeature(c, "u1", "can_x");
  assert(r.ok && r.granted === false);
});

Deno.test("callerHasFeature: role default used only when no override", async () => {
  const c = fakeClient(OK_USER, perms({}, { can_x: true }));
  const r = await callerHasFeature(c, "u1", "can_x");
  assert(r.ok && r.granted === true);
  const c2 = fakeClient(OK_USER, perms({}, { can_x: false }));
  const r2 = await callerHasFeature(c2, "u1", "can_x");
  assert(r2.ok && r2.granted === false);
});

Deno.test("callerHasFeature: override query error fails closed (no fall-through)", async () => {
  const canned: Canned = (table, _f, kind) => {
    if (table === "user_permissions" && kind === "single") return { data: null, error: { message: "boom" } };
    // a permissive default that MUST NOT be reached after the override error
    if (table === "role_permissions") return { data: [{ granted: true }], error: null };
    return { data: null, error: null };
  };
  const r = await callerHasFeature(fakeClient(OK_USER, canned), "u1", "can_x");
  assertEquals(r.ok, false);
});

Deno.test("authorizeAdmin: requires BOTH can_manage_users and can_manage_permissions", async () => {
  // has users, missing permissions → 403
  const c = fakeClient(OK_USER, perms({}, { can_manage_users: true, can_manage_permissions: false }));
  const r = await authorizeAdmin(c);
  assert(!r.ok);
  if (!r.ok) {
    assertEquals(r.status, 403);
    assert(r.message.includes("can_manage_permissions"));
  }
});

Deno.test("authorizeAdmin: both permissions present → ok", async () => {
  const c = fakeClient(OK_USER, perms({}, { can_manage_users: true, can_manage_permissions: true }));
  const r = await authorizeAdmin(c);
  assert(r.ok && r.uid === "u1");
});

Deno.test("authorizeAdmin: missing can_manage_users → 403", async () => {
  const c = fakeClient(OK_USER, perms({}, { can_manage_users: false, can_manage_permissions: true }));
  const r = await authorizeAdmin(c);
  assert(!r.ok);
  if (!r.ok) assertEquals(r.status, 403);
});

Deno.test("authorizeAdmin: a profile query error fails closed with 500", async () => {
  const canned: Canned = (table) => {
    if (table === "profiles") return { data: null, error: { message: "db down" } };
    return { data: null, error: null };
  };
  const r = await authorizeAdmin(fakeClient(OK_USER, canned));
  assert(!r.ok);
  if (!r.ok) assertEquals(r.status, 500);
});

Deno.test("authorizeAdmin: unauthenticated → 401", async () => {
  const c = fakeClient({ data: { user: null }, error: null }, perms({}, {}));
  const r = await authorizeAdmin(c);
  assert(!r.ok);
  if (!r.ok) assertEquals(r.status, 401);
});
