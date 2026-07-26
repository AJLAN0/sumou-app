// Backend unit tests for the pure Auth utilities. Run: `deno test` (no stack needed).
import {
  assert,
  assertEquals,
  assertFalse,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  buildInternalEmail,
  FORBIDDEN_KEYS,
  generateTempPassword,
  isValidUsername,
  normalizeUsername,
  TEMP_PASSWORD_LENGTH,
  validateCreateUserInput,
  validateResetPasswordInput,
} from "./auth-utils.ts";

Deno.test("normalizeUsername trims + lowercases", () => {
  assertEquals(normalizeUsername("  Admin.One  "), "admin.one");
  assertEquals(normalizeUsername("USER_2"), "user_2");
  assertEquals(normalizeUsername(123), "");
});

Deno.test("isValidUsername enforces ^[a-z0-9._-]{2,50}$", () => {
  assert(isValidUsername("admin"));
  assert(isValidUsername("a.b-c_1"));
  assertFalse(isValidUsername("a")); // too short
  assertFalse(isValidUsername("Admin")); // uppercase (must be normalized first)
  assertFalse(isValidUsername("has space"));
  assertFalse(isValidUsername("bad@char"));
  assertFalse(isValidUsername("x".repeat(51)));
});

Deno.test("buildInternalEmail uses the internal domain", () => {
  assertEquals(buildInternalEmail("admin"), "admin@users.sumou.internal");
});

Deno.test("temp password: length, classes, charset, uniqueness", () => {
  for (let i = 0; i < 200; i++) {
    const pw = generateTempPassword();
    assert(pw.length >= 16, "at least 16 chars");
    assertEquals(pw.length, TEMP_PASSWORD_LENGTH);
    assert(/[a-z]/.test(pw), "has lower");
    assert(/[A-Z]/.test(pw), "has upper");
    assert(/[0-9]/.test(pw), "has digit");
    assert(/[!@#$%^&*()\-_=+]/.test(pw), "has symbol");
    assertFalse(/[0O1lI]/.test(pw), "no ambiguous chars");
  }
  const a = generateTempPassword();
  const b = generateTempPassword();
  assert(a !== b, "two passwords differ");
});

Deno.test("input: valid minimal payload normalizes", () => {
  const r = validateCreateUserInput({
    username: "  New.User ",
    full_name: "  اسم كامل ",
    default_role: "photographer",
    roles: ["photographer"],
  });
  assert(r.ok);
  if (r.ok) {
    assertEquals(r.value.username, "new.user");
    assertEquals(r.value.full_name, "اسم كامل");
    assertEquals(r.value.photographer_types, []);
    assertEquals(r.value.permission_overrides, []);
  }
});

Deno.test("input: forbidden fields are rejected", () => {
  for (const k of FORBIDDEN_KEYS) {
    const body: Record<string, unknown> = {
      username: "user.x",
      full_name: "N",
      default_role: "manager",
      roles: ["manager"],
    };
    body[k] = "x";
    const r = validateCreateUserInput(body);
    assertFalse(r.ok, `must reject "${k}"`);
  }
});

Deno.test("input: malformed username / blank name rejected", () => {
  assertFalse(
    validateCreateUserInput({
      username: "a",
      full_name: "N",
      default_role: "manager",
      roles: ["manager"],
    }).ok,
  );
  assertFalse(
    validateCreateUserInput({
      username: "user",
      full_name: "   ",
      default_role: "manager",
      roles: ["manager"],
    }).ok,
  );
});

Deno.test("input: default role must be in roles; no duplicate roles", () => {
  assertFalse(
    validateCreateUserInput({
      username: "user",
      full_name: "N",
      default_role: "admin",
      roles: ["manager"],
    }).ok,
  );
  assertFalse(
    validateCreateUserInput({
      username: "user",
      full_name: "N",
      default_role: "manager",
      roles: ["manager", "manager"],
    }).ok,
  );
});

Deno.test("input: duplicate photographer types / overrides rejected", () => {
  assertFalse(
    validateCreateUserInput({
      username: "user",
      full_name: "N",
      default_role: "photographer",
      roles: ["photographer"],
      photographer_types: ["photo", "photo"],
    }).ok,
  );
  assertFalse(
    validateCreateUserInput({
      username: "user",
      full_name: "N",
      default_role: "manager",
      roles: ["manager"],
      permission_overrides: [{ code: "can_add_project", granted: true }, {
        code: "can_add_project",
        granted: false,
      }],
    }).ok,
  );
});

Deno.test("input: override needs a boolean granted + a code", () => {
  assertFalse(
    validateCreateUserInput({
      username: "user",
      full_name: "N",
      default_role: "manager",
      roles: ["manager"],
      permission_overrides: [{ code: "can_add_project", granted: "yes" }],
    }).ok,
  );
  assertFalse(
    validateCreateUserInput({
      username: "user",
      full_name: "N",
      default_role: "manager",
      roles: ["manager"],
      permission_overrides: [{ granted: true }],
    }).ok,
  );
});

Deno.test("input: valid overrides pass through", () => {
  const r = validateCreateUserInput({
    username: "user",
    full_name: "N",
    default_role: "manager",
    roles: ["manager", "photographer"],
    photographer_types: ["photo", "video"],
    permission_overrides: [{ code: "can_view_reports", granted: false }],
  });
  assert(r.ok);
  if (r.ok) {
    assertEquals(r.value.roles, ["manager", "photographer"]);
    assertEquals(r.value.permission_overrides, [{
      code: "can_view_reports",
      granted: false,
    }]);
  }
});

// ---- request framing + strict allowlist (added in the 10.2 hardening) -------
import {
  isJsonContentType,
  MAX_BODY_BYTES,
  readBoundedBody,
} from "./auth-utils.ts";

function streamOf(bytes: Uint8Array, chunk = 3): ReadableStream<Uint8Array> {
  let i = 0;
  return new ReadableStream<Uint8Array>({
    pull(controller) {
      if (i >= bytes.length) return controller.close();
      const end = Math.min(i + chunk, bytes.length);
      controller.enqueue(bytes.slice(i, end));
      i = end;
    },
  });
}

Deno.test("isJsonContentType: exact media type only (params allowed)", () => {
  assert(isJsonContentType("application/json"));
  assert(isJsonContentType("application/json; charset=utf-8"));
  assert(isJsonContentType("APPLICATION/JSON"));
  assertFalse(isJsonContentType("text/plain"));
  assertFalse(isJsonContentType("text/plain, application/json")); // must not merely contain
  assertFalse(isJsonContentType("application/jsonx"));
  assertFalse(isJsonContentType(null));
});

Deno.test("readBoundedBody: exactly at the limit passes", async () => {
  const bytes = new Uint8Array(10).fill(65); // 10 x 'A'
  const r = await readBoundedBody(streamOf(bytes), "10", 10);
  assert(r.ok);
  if (r.ok) assertEquals(r.bytes.length, 10);
});

Deno.test("readBoundedBody: over the limit is rejected (byte count)", async () => {
  const bytes = new Uint8Array(11).fill(65);
  const r = await readBoundedBody(streamOf(bytes), null, 10); // no Content-Length
  assertFalse(r.ok);
});

Deno.test("readBoundedBody: multibyte UTF-8 counts bytes, not chars", async () => {
  const bytes = new TextEncoder().encode("€€€€"); // 4 chars, 12 bytes
  assertEquals(bytes.length, 12);
  const over = await readBoundedBody(streamOf(bytes), null, 10);
  assertFalse(over.ok, "12 bytes > 10 → rejected");
  const ok = await readBoundedBody(streamOf(bytes), null, 12);
  assert(ok.ok, "12 bytes <= 12 → accepted");
});

Deno.test("readBoundedBody: rejects a lying/oversized Content-Length early", async () => {
  const r = await readBoundedBody(
    streamOf(new Uint8Array(1)),
    String(MAX_BODY_BYTES + 1),
    MAX_BODY_BYTES,
  );
  assertFalse(r.ok);
});

Deno.test("readBoundedBody: a big stream with a small Content-Length is still capped", async () => {
  const bytes = new Uint8Array(50).fill(66);
  const r = await readBoundedBody(streamOf(bytes), "3", 10); // header lies
  assertFalse(r.ok);
});

Deno.test("readBoundedBody: null body yields zero bytes", async () => {
  const r = await readBoundedBody(null, null, 10);
  assert(r.ok);
  if (r.ok) assertEquals(r.bytes.length, 0);
});

Deno.test("input: unknown top-level key rejected (not ignored)", () => {
  assertFalse(
    validateCreateUserInput({
      username: "user",
      full_name: "N",
      default_role: "manager",
      roles: ["manager"],
      extra: "x",
    }).ok,
  );
});

Deno.test("input: case-variant of a forbidden key is rejected as unknown", () => {
  for (const k of ["Password", "IS_ACTIVE", "User_Id", "Email"]) {
    const body: Record<string, unknown> = {
      username: "user",
      full_name: "N",
      default_role: "manager",
      roles: ["manager"],
    };
    body[k] = "x";
    assertFalse(validateCreateUserInput(body).ok, `reject "${k}"`);
  }
});

Deno.test("input: extra key inside a permission override is rejected", () => {
  assertFalse(
    validateCreateUserInput({
      username: "user",
      full_name: "N",
      default_role: "manager",
      roles: ["manager"],
      permission_overrides: [{
        code: "can_view_reports",
        granted: true,
        foo: 1,
      }],
    }).ok,
  );
});

// ---- validateResetPasswordInput (Step 10.3) ---------------------------------

Deno.test("reset input: a lone valid user_id passes and is lowercased", () => {
  const r = validateResetPasswordInput({
    user_id: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
  });
  assert(r.ok);
  if (r.ok) {
    assertEquals(r.value.user_id, "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee");
  }
});

Deno.test("reset input: non-object / array bodies rejected", () => {
  assertFalse(validateResetPasswordInput(null).ok);
  assertFalse(validateResetPasswordInput("x").ok);
  assertFalse(validateResetPasswordInput([]).ok);
});

Deno.test("reset input: missing user_id rejected", () => {
  assertFalse(validateResetPasswordInput({}).ok);
});

Deno.test("reset input: invalid UUID rejected", () => {
  assertFalse(validateResetPasswordInput({ user_id: "not-a-uuid" }).ok);
  assertFalse(validateResetPasswordInput({ user_id: "12345" }).ok);
  assertFalse(validateResetPasswordInput({ user_id: 123 }).ok);
});

Deno.test("reset input: unknown top-level field rejected (strict allowlist)", () => {
  assertFalse(
    validateResetPasswordInput({
      user_id: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
      extra: 1,
    }).ok,
  );
});

Deno.test("reset input: forbidden fields rejected (server-controlled)", () => {
  for (
    const k of [
      "password",
      "new_password",
      "temp_password",
      "email",
      "internal_email",
      "actor_id",
      "is_active",
      "must_change_password",
      "roles",
      "permissions",
      "username",
      "full_name",
    ]
  ) {
    const body: Record<string, unknown> = {
      user_id: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
    };
    body[k] = "x";
    assertFalse(
      validateResetPasswordInput(body).ok,
      `expected "${k}" rejected`,
    );
  }
});
