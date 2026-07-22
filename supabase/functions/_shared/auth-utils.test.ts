// Backend unit tests for the pure Auth utilities. Run: `deno test` (no stack needed).
import { assert, assertEquals, assertFalse } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  buildInternalEmail,
  FORBIDDEN_KEYS,
  generateTempPassword,
  isValidUsername,
  normalizeUsername,
  TEMP_PASSWORD_LENGTH,
  validateCreateUserInput,
} from "./auth-utils.ts";

Deno.test("normalizeUsername trims + lowercases", () => {
  assertEquals(normalizeUsername("  Admin.One  "), "admin.one");
  assertEquals(normalizeUsername("USER_2"), "user_2");
  assertEquals(normalizeUsername(123), "");
});

Deno.test("isValidUsername enforces ^[a-z0-9._-]{2,50}$", () => {
  assert(isValidUsername("admin"));
  assert(isValidUsername("a.b-c_1"));
  assertFalse(isValidUsername("a"));          // too short
  assertFalse(isValidUsername("Admin"));      // uppercase (must be normalized first)
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
    username: "  New.User ", full_name: "  اسم كامل ",
    default_role: "photographer", roles: ["photographer"],
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
      username: "user.x", full_name: "N", default_role: "manager", roles: ["manager"],
    };
    body[k] = "x";
    const r = validateCreateUserInput(body);
    assertFalse(r.ok, `must reject "${k}"`);
  }
});

Deno.test("input: malformed username / blank name rejected", () => {
  assertFalse(validateCreateUserInput({ username: "a", full_name: "N", default_role: "manager", roles: ["manager"] }).ok);
  assertFalse(validateCreateUserInput({ username: "user", full_name: "   ", default_role: "manager", roles: ["manager"] }).ok);
});

Deno.test("input: default role must be in roles; no duplicate roles", () => {
  assertFalse(validateCreateUserInput({ username: "user", full_name: "N", default_role: "admin", roles: ["manager"] }).ok);
  assertFalse(validateCreateUserInput({ username: "user", full_name: "N", default_role: "manager", roles: ["manager", "manager"] }).ok);
});

Deno.test("input: duplicate photographer types / overrides rejected", () => {
  assertFalse(validateCreateUserInput({
    username: "user", full_name: "N", default_role: "photographer", roles: ["photographer"],
    photographer_types: ["photo", "photo"],
  }).ok);
  assertFalse(validateCreateUserInput({
    username: "user", full_name: "N", default_role: "manager", roles: ["manager"],
    permission_overrides: [{ code: "can_add_project", granted: true }, { code: "can_add_project", granted: false }],
  }).ok);
});

Deno.test("input: override needs a boolean granted + a code", () => {
  assertFalse(validateCreateUserInput({
    username: "user", full_name: "N", default_role: "manager", roles: ["manager"],
    permission_overrides: [{ code: "can_add_project", granted: "yes" }],
  }).ok);
  assertFalse(validateCreateUserInput({
    username: "user", full_name: "N", default_role: "manager", roles: ["manager"],
    permission_overrides: [{ granted: true }],
  }).ok);
});

Deno.test("input: valid overrides pass through", () => {
  const r = validateCreateUserInput({
    username: "user", full_name: "N", default_role: "manager", roles: ["manager", "photographer"],
    photographer_types: ["photo", "video"],
    permission_overrides: [{ code: "can_view_reports", granted: false }],
  });
  assert(r.ok);
  if (r.ok) {
    assertEquals(r.value.roles, ["manager", "photographer"]);
    assertEquals(r.value.permission_overrides, [{ code: "can_view_reports", granted: false }]);
  }
});
