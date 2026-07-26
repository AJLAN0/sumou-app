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
const CURRENT_PASSWORD = "Curr3nt!Passw0rd";
const INTERNAL_EMAIL = "manager@users.sumou.internal";
const BEARER_TOKEN = "abc.def.ghi";

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
          ? Promise.reject(new Error(`getUser leaked ${BEARER_TOKEN}`))
          : Promise.resolve(getUser),
    },
    from: () => ({
      select: () => ({
        eq: () => ({
          maybeSingle: () =>
            opts.profileThrows
              ? Promise.reject(
                new Error(`profile leaked ${CURRENT_PASSWORD}`),
              )
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
            return Promise.reject(
              new Error(`Auth leaked ${GOOD_NEW} ${INTERNAL_EMAIL}`),
            );
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
      if (opts.rpcThrows) {
        return Promise.reject(
          new Error(`RPC leaked ${GOOD_NEW} ${BEARER_TOKEN}`),
        );
      }
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

// deno-lint-ignore no-explicit-any
function fakeClientFactory(clients: any[]) {
  const createdWithKeys: string[] = [];
  let anonIndex = 0;
  return {
    createdWithKeys,
    factory: (_url: string, key: string) => {
      createdWithKeys.push(key);
      if (key === "service-test-key") return clients[2];
      return clients[anonIndex++];
    },
  };
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
    bearer = `Bearer ${BEARER_TOKEN}` as string | null,
  } = {},
): Request {
  const headers: Record<string, string> = {};
  if (contentType !== null) headers["content-type"] = contentType;
  if (bearer !== null) headers["authorization"] = bearer;
  return new Request("http://x", { method, headers, body });
}

function validReq(): Request {
  return req(JSON.stringify({
    current_password: CURRENT_PASSWORD,
    new_password: GOOD_NEW,
  }));
}

async function assertSafeErrorResponse(
  res: Response,
  expectedStatus: number,
): Promise<{ error: { code: string; message: string } }> {
  assertEquals(res.status, expectedStatus);
  assertEquals(res.headers.get("Content-Type"), "application/json");
  assertEquals(res.headers.get("Cache-Control"), "no-store, max-age=0");
  assertEquals(res.headers.get("Pragma"), "no-cache");
  assertEquals(res.headers.get("X-Content-Type-Options"), "nosniff");

  const text = await res.text();
  for (
    const secret of [
      CURRENT_PASSWORD,
      GOOD_NEW,
      INTERNAL_EMAIL,
      BEARER_TOKEN,
      "anon-test-key",
      "service-test-key",
      "access_token",
    ]
  ) {
    assert(!text.includes(secret), `response leaked "${secret}"`);
  }
  return JSON.parse(text);
}

// ---- request framing --------------------------------------------------------

Deno.test("handleRequest: GET → 405 + Allow: POST", async () => {
  const res = await handleRequest(new Request("http://x", { method: "GET" }));
  await assertSafeErrorResponse(res, 405);
  assertEquals(res.headers.get("Allow"), "POST");
});

Deno.test("handleRequest: wrong Content-Type → 415", async () => {
  const res = await handleRequest(req("{}", { contentType: "text/plain" }));
  await assertSafeErrorResponse(res, 415);
});

Deno.test("handleRequest: missing bearer → 401", async () => {
  const res = await handleRequest(req("{}", { bearer: null }));
  await assertSafeErrorResponse(res, 401);
});

Deno.test("handleRequest: malformed JSON → 400", async () => {
  const res = await handleRequest(req("{"));
  const body = await assertSafeErrorResponse(res, 400);
  assertEquals(body.error.code, "invalid_request");
});

Deno.test("handleRequest: unknown field → 400 (strict allowlist)", async () => {
  const res = await handleRequest(
    req(JSON.stringify({
      current_password: "x",
      new_password: GOOD_NEW,
      username: "x",
    })),
  );
  await assertSafeErrorResponse(res, 400);
});

Deno.test("handleRequest: weak new_password → 400 weak_password (pre-network)", async () => {
  const res = await handleRequest(
    req(
      JSON.stringify({ current_password: "whatever", new_password: "short" }),
    ),
  );
  const body = await assertSafeErrorResponse(res, 400);
  assertEquals(body.error.code, "weak_password");
});

Deno.test("handleRequest: same new/current password → 400 (pre-network)", async () => {
  const res = await handleRequest(
    req(JSON.stringify({ current_password: GOOD_NEW, new_password: GOOD_NEW })),
  );
  const body = await assertSafeErrorResponse(res, 400);
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

Deno.test("authorizeActiveStaff: normalized username is returned", async () => {
  const r = await authorizeActiveStaff(
    fakeUserClient(OK_USER, {
      data: { id: "u1", is_active: true, username: "  Manager  " },
      error: null,
    }),
  );
  assert(r.ok);
  if (r.ok) assertEquals(r.username, "manager");
});

// ---- re-authentication (current password) -----------------------------------

Deno.test("reauthenticate: correct password → success", async () => {
  const result = await reauthenticate(
    fakeAnonClient({ data: { session: { access_token: "t" } }, error: null }),
    INTERNAL_EMAIL,
    "current",
  );
  assertEquals(result, "success");
});

Deno.test("reauthenticate: confirmed wrong password → invalidCredentials", async () => {
  const result = await reauthenticate(
    fakeAnonClient({
      data: { session: null },
      error: { code: "invalid_credentials", message: "invalid" },
    }),
    INTERNAL_EMAIL,
    "wrong",
  );
  assertEquals(result, "invalidCredentials");
});

Deno.test("reauthenticate: no session in response → serverError", async () => {
  const result = await reauthenticate(
    fakeAnonClient({ data: { session: null }, error: null }),
    INTERNAL_EMAIL,
    "x",
  );
  assertEquals(result, "serverError");
});

Deno.test("reauthenticate: thrown error → serverError", async () => {
  const result = await reauthenticate(
    fakeAnonClient({ data: null, error: null }, { throws: true }),
    INTERNAL_EMAIL,
    "x",
  );
  assertEquals(result, "serverError");
});

Deno.test("reauthenticate: rate limit/unexpected Auth error → serverError", async () => {
  for (const code of ["over_request_rate_limit", "unexpected_failure"]) {
    const result = await reauthenticate(
      fakeAnonClient({
        data: { session: null },
        error: { code, message: `must not leak ${CURRENT_PASSWORD}` },
      }),
      INTERNAL_EMAIL,
      CURRENT_PASSWORD,
    );
    assertEquals(result, "serverError");
  }
});

// ---- hardened HTTP failure paths --------------------------------------------

Deno.test("handleRequest: getUser throws → safe 500", async () => {
  const f = fakeClientFactory([
    fakeUserClient(OK_USER, ACTIVE_PROFILE, { getUserThrows: true }),
  ]);
  const res = await handleRequest(validReq(), f.factory);
  const body = await assertSafeErrorResponse(res, 500);
  assertEquals(body.error.code, "server_error");
  assertEquals(f.createdWithKeys, ["anon-test-key"]);
});

Deno.test("handleRequest: profile query throws → safe 500", async () => {
  const f = fakeClientFactory([
    fakeUserClient(OK_USER, ACTIVE_PROFILE, { profileThrows: true }),
  ]);
  const res = await handleRequest(validReq(), f.factory);
  const body = await assertSafeErrorResponse(res, 500);
  assertEquals(body.error.code, "server_error");
  assertEquals(f.createdWithKeys, ["anon-test-key"]);
});

Deno.test("handleRequest: malformed username/id rejected before re-auth/service clients", async () => {
  for (
    const profile of [
      {
        data: { id: "different-user", is_active: true, username: "manager" },
        error: null,
      },
      {
        data: { id: "u1", is_active: true, username: "bad name" },
        error: null,
      },
    ]
  ) {
    const f = fakeClientFactory([fakeUserClient(OK_USER, profile)]);
    const res = await handleRequest(validReq(), f.factory);
    const body = await assertSafeErrorResponse(res, 500);
    assertEquals(body.error.code, "server_error");
    // Only the caller-scoped client exists; neither re-auth nor service exists.
    assertEquals(f.createdWithKeys, ["anon-test-key"]);
  }
});

Deno.test("handleRequest: confirmed wrong current password → 401", async () => {
  const f = fakeClientFactory([
    fakeUserClient(OK_USER, ACTIVE_PROFILE),
    fakeAnonClient({
      data: { session: null },
      error: {
        code: "invalid_credentials",
        message: `must not leak ${CURRENT_PASSWORD}`,
      },
    }),
  ]);
  const res = await handleRequest(validReq(), f.factory);
  const body = await assertSafeErrorResponse(res, 401);
  assertEquals(body.error.code, "invalid_credentials");
  assertEquals(f.createdWithKeys, ["anon-test-key", "anon-test-key"]);
});

Deno.test("handleRequest: re-auth network/service errors → safe 500", async () => {
  const failures = [
    fakeAnonClient({ data: null, error: null }, { throws: true }),
    fakeAnonClient({
      data: { session: null },
      error: {
        code: "over_request_rate_limit",
        message: `must not leak ${INTERNAL_EMAIL}`,
      },
    }),
  ];
  for (const failure of failures) {
    const f = fakeClientFactory([
      fakeUserClient(OK_USER, ACTIVE_PROFILE),
      failure,
    ]);
    const res = await handleRequest(validReq(), f.factory);
    const body = await assertSafeErrorResponse(res, 500);
    assertEquals(body.error.code, "server_error");
    assertEquals(f.createdWithKeys, ["anon-test-key", "anon-test-key"]);
  }
});

Deno.test("handleRequest: updateUserById throws → safe 500 and RPC skipped", async () => {
  const service = fakeService({ updateThrows: true });
  const f = fakeClientFactory([
    fakeUserClient(OK_USER, ACTIVE_PROFILE),
    fakeAnonClient({
      data: { session: { access_token: BEARER_TOKEN } },
      error: null,
    }),
    service.client,
  ]);
  const res = await handleRequest(validReq(), f.factory);
  const body = await assertSafeErrorResponse(res, 500);
  assertEquals(body.error.code, "server_error");
  assertEquals(service.calls, ["update"]);
});

Deno.test("handleRequest: RPC throws after Auth update → safe 500 partial failure", async () => {
  const service = fakeService({ rpcThrows: true });
  const f = fakeClientFactory([
    fakeUserClient(OK_USER, ACTIVE_PROFILE),
    fakeAnonClient({
      data: { session: { access_token: BEARER_TOKEN } },
      error: null,
    }),
    service.client,
  ]);
  const res = await handleRequest(validReq(), f.factory);
  const body = await assertSafeErrorResponse(res, 500);
  assertEquals(body.error.code, "server_error");
  assertEquals(service.calls, ["update", "rpc:record_own_password_change"]);
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
  await assertSafeErrorResponse(res, 500);
  assert(!f.calls.some((c) => c.startsWith("rpc:"))); // RPC skipped
});

Deno.test("performOwnPasswordChange: RPC fails AFTER Auth update → generic 500", async () => {
  const f = fakeService({
    rpcResult: { data: null, error: { message: "flag failed" } },
  });
  const res = await performOwnPasswordChange(f.client, "u1", GOOD_NEW);
  await assertSafeErrorResponse(res, 500);
  // Auth update ran, then the RPC ran and failed — order proves the sequence.
  assertEquals(f.calls, ["update", "rpc:record_own_password_change"]);
});
