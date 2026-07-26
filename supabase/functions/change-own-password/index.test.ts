// Unit tests for the change-own-password Edge Function, using hand-rolled fake
// Supabase clients (no running stack). Importing index.ts does NOT start a server
// (Deno.serve is guarded by import.meta.main).
//
// Covered: request framing (405/415/401/400), strict body allowlist, the
// new-password policy, the differ-from-current rule, own-active-staff
// authorization (no admin/permission needed), current-password re-auth, and the
// Auth→DB ordering / partial-failure behavior of performOwnPasswordChange.
import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  validateNewPassword,
  validatePasswordChangeInput,
} from "../_shared/auth-utils.ts";
import {
  authorizeActiveStaff,
  handleRequest,
  performOwnPasswordChange,
  reauthenticate,
} from "./index.ts";

// Env is read by handleRequest AFTER method/content-type/bearer checks; set dummy
// values so the body/policy/same-password paths (which return BEFORE any network
// client is built) are reachable. Never real secrets.
Deno.env.set("SUPABASE_URL", "http://localhost");
Deno.env.set("SUPABASE_ANON_KEY", "anon-test-key");
Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "service-test-key");

type QueryResult = { data: unknown; error: unknown };

const GOOD_NEW = "Str0ng!Passw0rd"; // 15 chars: upper/lower/digit/symbol

// ---- fakes ------------------------------------------------------------------

// deno-lint-ignore no-explicit-any
function fakeUserClient(
  getUser: QueryResult,
  profile: QueryResult,
  opts: { getUserThrows?: boolean; profileThrows?: boolean } = {},
): any {
  return {
    auth: {
      getUser: () =>
        opts.getUserThrows
          ? Promise.reject(new Error("getUser network"))
          : Promise.resolve(getUser),
    },
    from: () => ({
      select: () => ({
        eq: () => ({
          maybeSingle: () =>
            opts.profileThrows
              ? Promise.reject(new Error("profile network"))
              : Promise.resolve(profile),
        }),
      }),
    }),
  };
}

// deno-lint-ignore no-explicit-any
function fakeAnonClient(
  result: QueryResult,
  opts: { throws?: boolean } = {},
): any {
  return {
    auth: {
      signInWithPassword: () =>
        opts.throws
          ? Promise.reject(new Error("network"))
          : Promise.resolve(result),
    },
  };
}

function fakeService(opts: {
  updateResult?: { data: unknown; error: unknown };
  rpcResult?: QueryResult;
  updateThrows?: boolean;
  rpcThrows?: boolean;
}) {
  const calls: string[] = [];
  const updateArgs: { id?: string; password?: string } = {};
  const rpcArgs: Record<string, unknown> = {};
  // deno-lint-ignore no-explicit-any
  const client: any = {
    auth: {
      admin: {
        updateUserById: (id: string, o: { password: string }) => {
          calls.push("update");
          updateArgs.id = id;
          updateArgs.password = o.password;
          if (opts.updateThrows) {
            return Promise.reject(new Error("updateUserById network"));
          }
          return Promise.resolve(
            opts.updateResult ?? { data: { user: { id } }, error: null },
          );
        },
      },
    },
    rpc: (name: string, args: Record<string, unknown>) => {
      calls.push("rpc:" + name);
      Object.assign(rpcArgs, args);
      if (opts.rpcThrows) return Promise.reject(new Error("rpc network"));
      return Promise.resolve(
        opts.rpcResult ??
          {
            data: { id: "u1", must_change_password: false, is_active: true },
            error: null,
          },
      );
    },
  };
  return { client, calls, updateArgs, rpcArgs };
}

const OK_USER: QueryResult = { data: { user: { id: "u1" } }, error: null };
const ACTIVE_PROFILE: QueryResult = {
  data: { id: "u1", is_active: true, username: "manager" },
  error: null,
};

function req(
  body: string,
  {
    method = "POST",
    contentType = "application/json" as string | null,
    bearer = "Bearer abc.def.ghi" as string | null,
  } = {},
): Request {
  const headers: Record<string, string> = {};
  if (contentType !== null) headers["content-type"] = contentType;
  if (bearer !== null) headers["authorization"] = bearer;
  return new Request("http://x", { method, headers, body });
}

// ---- request framing --------------------------------------------------------

Deno.test("handleRequest: GET → 405 + Allow: POST", async () => {
  const res = await handleRequest(new Request("http://x", { method: "GET" }));
  assertEquals(res.status, 405);
  assertEquals(res.headers.get("Allow"), "POST");
  assertEquals(res.headers.get("Cache-Control"), "no-store, max-age=0");
});

Deno.test("handleRequest: wrong Content-Type → 415", async () => {
  const res = await handleRequest(req("{}", { contentType: "text/plain" }));
  assertEquals(res.status, 415);
});

Deno.test("handleRequest: missing bearer → 401", async () => {
  const res = await handleRequest(req("{}", { bearer: null }));
  assertEquals(res.status, 401);
});

Deno.test("handleRequest: malformed JSON → 400", async () => {
  const res = await handleRequest(req("{"));
  assertEquals(res.status, 400);
  assertEquals((await res.json()).error.code, "invalid_request");
});

Deno.test("handleRequest: unknown field → 400 (strict allowlist)", async () => {
  const res = await handleRequest(
    req(JSON.stringify({
      current_password: "x",
      new_password: GOOD_NEW,
      username: "x",
    })),
  );
  assertEquals(res.status, 400);
});

Deno.test("handleRequest: weak new_password → 400 weak_password (pre-network)", async () => {
  const res = await handleRequest(
    req(
      JSON.stringify({ current_password: "whatever", new_password: "short" }),
    ),
  );
  assertEquals(res.status, 400);
  assertEquals((await res.json()).error.code, "weak_password");
});

Deno.test("handleRequest: same new/current password → 400 (pre-network)", async () => {
  const res = await handleRequest(
    req(JSON.stringify({ current_password: GOOD_NEW, new_password: GOOD_NEW })),
  );
  assertEquals(res.status, 400);
  const body = await res.json();
  assert(body.error.message.includes("differ"));
});

// ---- body allowlist + policy (pure) -----------------------------------------

Deno.test("validatePasswordChangeInput: strict allowlist + required strings", () => {
  assert(
    validatePasswordChangeInput({ current_password: "a", new_password: "b" })
      .ok,
  );
  assert(!validatePasswordChangeInput({ current_password: "a" }).ok);
  assert(!validatePasswordChangeInput({ new_password: "b" }).ok);
  assert(
    !validatePasswordChangeInput({
      current_password: "a",
      new_password: "b",
      extra: 1,
    }).ok,
  );
  for (const k of ["username", "email", "user_id", "id", "token", "password"]) {
    const body: Record<string, unknown> = {
      current_password: "a",
      new_password: "b",
    };
    body[k] = "x";
    assert(!validatePasswordChangeInput(body).ok, `must reject "${k}"`);
  }
  assert(
    !validatePasswordChangeInput({
      current_password: "",
      new_password: "b",
    }).ok,
  );
  assert(!validatePasswordChangeInput("x").ok);
});

Deno.test("validateNewPassword: policy (12-72, classes, no edge whitespace)", () => {
  assert(validateNewPassword(GOOD_NEW).ok);
  assert(validateNewPassword("A".repeat(1) + "a1!bcdefghij").ok); // 13, all classes
  assert(!validateNewPassword("Ab1!").ok); // too short
  assert(!validateNewPassword("A1!" + "a".repeat(70)).ok); // 73 > 72
  assert(!validateNewPassword("alllowercase1!").ok); // no uppercase
  assert(!validateNewPassword("ALLUPPERCASE1!").ok); // no lowercase
  assert(!validateNewPassword("NoDigitsHere!!").ok); // no digit
  assert(!validateNewPassword("NoSymbol1234A").ok); // no symbol
  assert(!validateNewPassword(" Str0ng!Passw0rd").ok); // leading ws
  assert(!validateNewPassword("Str0ng!Passw0rd ").ok); // trailing ws
  assert(!validateNewPassword(123).ok); // not a string
});

// ---- authorization (own active staff; no admin/permission) ------------------

Deno.test("authorizeActiveStaff: active caller → ok with uid + username", async () => {
  const r = await authorizeActiveStaff(
    fakeUserClient(OK_USER, ACTIVE_PROFILE),
  );
  assert(r.ok);
  if (r.ok) {
    assertEquals(r.uid, "u1");
    assertEquals(r.username, "manager");
  }
});

Deno.test("authorizeActiveStaff: unauthenticated → 401", async () => {
  const r = await authorizeActiveStaff(
    fakeUserClient({ data: { user: null }, error: null }, ACTIVE_PROFILE),
  );
  assert(!r.ok);
  if (!r.ok) assertEquals(r.status, 401);
});

Deno.test("authorizeActiveStaff: inactive/deleted/missing profile (no row) → 403", async () => {
  const r = await authorizeActiveStaff(
    fakeUserClient(OK_USER, { data: null, error: null }),
  );
  assert(!r.ok);
  if (!r.ok) assertEquals(r.status, 403);
});

Deno.test("authorizeActiveStaff: is_active=false → 403", async () => {
  const r = await authorizeActiveStaff(
    fakeUserClient(OK_USER, {
      data: { id: "u1", is_active: false, username: "manager" },
      error: null,
    }),
  );
  assert(!r.ok);
  if (!r.ok) assertEquals(r.status, 403);
});

Deno.test("authorizeActiveStaff: profile query error → 500 (fail closed)", async () => {
  const r = await authorizeActiveStaff(
    fakeUserClient(OK_USER, { data: null, error: { message: "db down" } }),
  );
  assert(!r.ok);
  if (!r.ok) assertEquals(r.status, 500);
});

Deno.test("authorizeActiveStaff: getUser THROWS → safe 500", async () => {
  const r = await authorizeActiveStaff(
    fakeUserClient(OK_USER, ACTIVE_PROFILE, { getUserThrows: true }),
  );
  assert(!r.ok);
  if (!r.ok) {
    assertEquals(r.status, 500);
    assertEquals(r.code, "server_error");
  }
});

Deno.test("authorizeActiveStaff: profile query THROWS → safe 500", async () => {
  const r = await authorizeActiveStaff(
    fakeUserClient(OK_USER, ACTIVE_PROFILE, { profileThrows: true }),
  );
  assert(!r.ok);
  if (!r.ok) assertEquals(r.status, 500);
});

Deno.test("authorizeActiveStaff: malformed username → 500 (fail closed pre-reauth)", async () => {
  for (const bad of ["Manager", "has space", "a", "x".repeat(51), "bad@char"]) {
    const r = await authorizeActiveStaff(
      fakeUserClient(OK_USER, {
        data: { id: "u1", is_active: true, username: bad },
        error: null,
      }),
    );
    assert(!r.ok, `username "${bad}" must be rejected`);
    if (!r.ok) assertEquals(r.status, 500);
  }
});

Deno.test("authorizeActiveStaff: profile id != uid → 500 (fail closed)", async () => {
  const r = await authorizeActiveStaff(
    fakeUserClient(OK_USER, {
      data: { id: "someone-else", is_active: true, username: "manager" },
      error: null,
    }),
  );
  assert(!r.ok);
  if (!r.ok) assertEquals(r.status, 500);
});

// ---- re-authentication (typed result) ---------------------------------------

Deno.test("reauthenticate: correct password → success", async () => {
  const r = await reauthenticate(
    fakeAnonClient({ data: { session: { access_token: "t" } }, error: null }),
    "manager@users.sumou.internal",
    "current",
  );
  assertEquals(r, "success");
});

Deno.test("reauthenticate: CONFIRMED wrong password → invalidCredentials", async () => {
  // GoTrue error code path.
  const byCode = await reauthenticate(
    fakeAnonClient({
      data: { session: null },
      error: { code: "invalid_credentials", status: 400, message: "x" },
    }),
    "manager@users.sumou.internal",
    "wrong",
  );
  assertEquals(byCode, "invalidCredentials");
  // 400 + "Invalid login credentials" message path.
  const byMessage = await reauthenticate(
    fakeAnonClient({
      data: { session: null },
      error: { status: 400, message: "Invalid login credentials" },
    }),
    "manager@users.sumou.internal",
    "wrong",
  );
  assertEquals(byMessage, "invalidCredentials");
});

Deno.test("reauthenticate: rate limit / unexpected Auth error → serverError (not 401)", async () => {
  const rate = await reauthenticate(
    fakeAnonClient({
      data: { session: null },
      error: { code: "over_request_rate_limit", status: 429, message: "slow" },
    }),
    "manager@users.sumou.internal",
    "x",
  );
  assertEquals(rate, "serverError");
  const unexpected = await reauthenticate(
    fakeAnonClient({
      data: { session: null },
      error: { status: 500, message: "internal" },
    }),
    "manager@users.sumou.internal",
    "x",
  );
  assertEquals(unexpected, "serverError");
});

Deno.test("reauthenticate: no error but no session → serverError", async () => {
  const r = await reauthenticate(
    fakeAnonClient({ data: { session: null }, error: null }),
    "manager@users.sumou.internal",
    "x",
  );
  assertEquals(r, "serverError");
});

Deno.test("reauthenticate: THROWN error → serverError (no leak)", async () => {
  const r = await reauthenticate(
    fakeAnonClient({ data: null, error: null }, { throws: true }),
    "manager@users.sumou.internal",
    "x",
  );
  assertEquals(r, "serverError");
});

// ---- performOwnPasswordChange: ordering / partial failure -------------------

Deno.test("performOwnPasswordChange: success → 200, Auth update on exact uid, then RPC", async () => {
  const f = fakeService({});
  const res = await performOwnPasswordChange(f.client, "u1", GOOD_NEW);
  assertEquals(res.status, 200);
  assertEquals(f.updateArgs.id, "u1"); // ONLY the caller's uid
  assertEquals(f.updateArgs.password, GOOD_NEW);
  assertEquals(f.calls, ["update", "rpc:record_own_password_change"]); // order
  assertEquals(f.rpcArgs.p_user_id, "u1");
  // No secret in the success body.
  const body = await res.json();
  assert(!("password" in body));
  assert(!JSON.stringify(body).includes(GOOD_NEW));
  assert(!JSON.stringify(body).includes("@users.sumou.internal"));
  assertEquals(body.user.must_change_password, false);
});

Deno.test("performOwnPasswordChange: Auth update fails → 500, RPC NOT called", async () => {
  const f = fakeService({
    updateResult: { data: null, error: { message: "auth down" } },
  });
  const res = await performOwnPasswordChange(f.client, "u1", GOOD_NEW);
  assertEquals(res.status, 500);
  assert(!f.calls.some((c) => c.startsWith("rpc:"))); // RPC skipped
  const body = await res.json();
  assert(!JSON.stringify(body).includes(GOOD_NEW));
});

Deno.test("performOwnPasswordChange: RPC fails AFTER Auth update → generic 500", async () => {
  const f = fakeService({
    rpcResult: { data: null, error: { message: "flag failed" } },
  });
  const res = await performOwnPasswordChange(f.client, "u1", GOOD_NEW);
  assertEquals(res.status, 500);
  // Auth update ran, then the RPC ran and failed — order proves the sequence.
  assertEquals(f.calls, ["update", "rpc:record_own_password_change"]);
  const body = await res.json();
  assert(!JSON.stringify(body).includes(GOOD_NEW)); // no secret leak
});
