// Auth backend utilities — pure, dependency-free, unit-testable.
// Used by the admin-create-user Edge Function. No secrets, no I/O here.

export const USERNAME_RE = /^[a-z0-9._-]{2,50}$/;
export const INTERNAL_EMAIL_DOMAIN = "users.sumou.internal";

/** Frozen deterministic normalization: trim + lowercase. */
export function normalizeUsername(raw: unknown): string {
  return typeof raw === "string" ? raw.trim().toLowerCase() : "";
}

export function isValidUsername(normalized: string): boolean {
  return USERNAME_RE.test(normalized);
}

/**
 * The hidden internal Auth email. Constructed ONLY in the trusted Edge Function;
 * never accepted from the client, never returned or logged.
 */
export function buildInternalEmail(normalizedUsername: string): string {
  return `${normalizedUsername}@${INTERNAL_EMAIL_DOMAIN}`;
}

// ---- temporary password -----------------------------------------------------
// Cryptographically secure. Unambiguous character set (no 0/O/1/l/I). >= 16 chars
// with at least one of each class (lower, upper, digit, symbol) so it satisfies a
// typical Supabase password policy. Never stored/logged; returned once by HTTP.
const PW_LOWER = "abcdefghijkmnpqrstuvwxyz"; // no l, o
const PW_UPPER = "ABCDEFGHJKLMNPQRSTUVWXYZ"; // no I, O
const PW_DIGIT = "23456789"; // no 0, 1
const PW_SYMBOL = "!@#$%^&*()-_=+";
const PW_ALL = PW_LOWER + PW_UPPER + PW_DIGIT + PW_SYMBOL;
export const TEMP_PASSWORD_LENGTH = 20;

/** Uniform random int in [0, max) via rejection sampling (no modulo bias). */
function secureRandomInt(max: number): number {
  if (max <= 0) throw new Error("max must be > 0");
  const limit = Math.floor(0xffffffff / max) * max;
  const buf = new Uint32Array(1);
  let x = 0;
  do {
    crypto.getRandomValues(buf);
    x = buf[0];
  } while (x >= limit);
  return x % max;
}

function pick(chars: string): string {
  return chars[secureRandomInt(chars.length)];
}

/** Secure Fisher–Yates shuffle. */
function shuffle<T>(arr: T[]): T[] {
  for (let i = arr.length - 1; i > 0; i--) {
    const j = secureRandomInt(i + 1);
    [arr[i], arr[j]] = [arr[j], arr[i]];
  }
  return arr;
}

export function generateTempPassword(length = TEMP_PASSWORD_LENGTH): string {
  const n = Math.max(16, length);
  const chars: string[] = [
    pick(PW_LOWER),
    pick(PW_UPPER),
    pick(PW_DIGIT),
    pick(PW_SYMBOL),
  ];
  while (chars.length < n) chars.push(pick(PW_ALL));
  return shuffle(chars).join("");
}

// ---- request input validation ----------------------------------------------
export const MAX_BODY_BYTES = 8 * 1024; // generous for identity metadata

/** Keys the client must NEVER supply (identity/authorization are server-derived). */
export const FORBIDDEN_KEYS = [
  "password",
  "temp_password",
  "tempPassword",
  "email",
  "internal_email",
  "internalEmail",
  "id",
  "user_id",
  "userId",
  "uuid",
  "actor_id",
  "actorId",
  "is_active",
  "isActive",
  "must_change_password",
  "mustChangePassword",
  "audit",
  "meta",
];

/** The ONLY top-level keys accepted (strict allowlist — unknown keys rejected). */
export const ALLOWED_TOP_LEVEL_KEYS = [
  "username",
  "full_name",
  "default_role",
  "roles",
  "photographer_types",
  "permission_overrides",
] as const;
/** The ONLY keys accepted inside a permission override object. */
export const ALLOWED_OVERRIDE_KEYS = ["code", "granted"] as const;

export interface PermissionOverride {
  code: string;
  granted: boolean;
}
export interface CreateUserInput {
  username: string;
  full_name: string;
  default_role: string;
  roles: string[];
  photographer_types: string[];
  permission_overrides: PermissionOverride[];
}
export type ValidationResult =
  | { ok: true; value: CreateUserInput }
  | { ok: false; error: string };

function isStringArray(v: unknown): v is string[] {
  return Array.isArray(v) && v.every((x) => typeof x === "string");
}
function hasDuplicates(xs: string[]): boolean {
  return new Set(xs).size !== xs.length;
}

/**
 * Structural validation + normalization only. Catalog validity (active roles /
 * types / permissions) is enforced authoritatively by create_staff_profile.
 */
export function validateCreateUserInput(body: unknown): ValidationResult {
  if (body === null || typeof body !== "object" || Array.isArray(body)) {
    return { ok: false, error: "request body must be a JSON object" };
  }
  const o = body as Record<string, unknown>;

  // explicit forbidden keys first (specific message), then a STRICT allowlist:
  // every unknown top-level key is rejected, not ignored.
  for (const k of FORBIDDEN_KEYS) {
    if (k in o) return { ok: false, error: `field "${k}" is not allowed` };
  }
  const allowed = new Set<string>(ALLOWED_TOP_LEVEL_KEYS);
  for (const k of Object.keys(o)) {
    if (!allowed.has(k)) return { ok: false, error: `unknown field "${k}"` };
  }

  const username = normalizeUsername(o.username);
  if (!isValidUsername(username)) {
    return { ok: false, error: "username must match ^[a-z0-9._-]{2,50}$" };
  }

  const full_name = typeof o.full_name === "string" ? o.full_name.trim() : "";
  if (full_name === "") return { ok: false, error: "full_name is required" };

  if (typeof o.default_role !== "string" || o.default_role.trim() === "") {
    return { ok: false, error: "default_role is required" };
  }
  const default_role = o.default_role;

  if (!isStringArray(o.roles) || o.roles.length === 0) {
    return { ok: false, error: "roles must be a non-empty string array" };
  }
  const roles = o.roles;
  if (hasDuplicates(roles)) return { ok: false, error: "duplicate role" };
  if (!roles.includes(default_role)) {
    return { ok: false, error: "default_role must be included in roles" };
  }

  let photographer_types: string[] = [];
  if (o.photographer_types !== undefined) {
    if (!isStringArray(o.photographer_types)) {
      return { ok: false, error: "photographer_types must be a string array" };
    }
    photographer_types = o.photographer_types;
    if (hasDuplicates(photographer_types)) {
      return { ok: false, error: "duplicate photographer type" };
    }
  }

  let permission_overrides: PermissionOverride[] = [];
  if (o.permission_overrides !== undefined) {
    if (!Array.isArray(o.permission_overrides)) {
      return { ok: false, error: "permission_overrides must be an array" };
    }
    const seen = new Set<string>();
    for (const raw of o.permission_overrides) {
      if (raw === null || typeof raw !== "object" || Array.isArray(raw)) {
        return {
          ok: false,
          error: "each permission override must be an object",
        };
      }
      const ov = raw as Record<string, unknown>;
      for (const key of Object.keys(ov)) {
        if (key !== "code" && key !== "granted") {
          return {
            ok: false,
            error: `unknown permission override field "${key}"`,
          };
        }
      }
      if (typeof ov.code !== "string" || ov.code.trim() === "") {
        return { ok: false, error: "permission override needs a code" };
      }
      if (typeof ov.granted !== "boolean") {
        return {
          ok: false,
          error: "permission override needs a boolean granted",
        };
      }
      if (seen.has(ov.code)) {
        return { ok: false, error: "duplicate permission override" };
      }
      seen.add(ov.code);
      permission_overrides.push({ code: ov.code, granted: ov.granted });
    }
  }

  return {
    ok: true,
    value: {
      username,
      full_name,
      default_role,
      roles,
      photographer_types,
      permission_overrides,
    },
  };
}

// ---- request framing helpers ------------------------------------------------

/**
 * True only when the media type is EXACTLY `application/json` (params like
 * `; charset=utf-8` are allowed). Rejects strings that merely CONTAIN the token,
 * e.g. `text/plain, application/json`.
 */
export function isJsonContentType(header: string | null): boolean {
  if (!header) return false;
  const mediaType = header.split(";", 1)[0].trim().toLowerCase();
  return mediaType === "application/json";
}

export type BoundedBody =
  | { ok: true; bytes: Uint8Array }
  | { ok: false; reason: "too_large" };

/**
 * Read a request body into bytes with a hard cap, WITHOUT buffering an oversized
 * request. Rejects early on a too-large Content-Length (when present, but never
 * trusted alone), then streams incrementally counting ACTUAL bytes and cancels
 * the moment the cap is exceeded. UTF-8 is decoded by the caller only after the
 * bounded bytes are collected. A null body yields zero bytes.
 */
export async function readBoundedBody(
  body: ReadableStream<Uint8Array> | null,
  contentLength: string | null,
  maxBytes: number,
): Promise<BoundedBody> {
  if (contentLength != null && contentLength !== "") {
    const declared = Number(contentLength);
    if (Number.isFinite(declared) && declared > maxBytes) {
      return { ok: false, reason: "too_large" };
    }
  }
  if (body == null) return { ok: true, bytes: new Uint8Array(0) };

  const reader = body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      if (!value) continue;
      total += value.byteLength;
      if (total > maxBytes) {
        await reader.cancel();
        return { ok: false, reason: "too_large" };
      }
      chunks.push(value);
    }
  } finally {
    try {
      reader.releaseLock();
    } catch { /* already released */ }
  }

  const out = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    out.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return { ok: true, bytes: out };
}
