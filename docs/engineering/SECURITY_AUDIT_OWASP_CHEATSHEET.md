# Security Audit / OWASP Vulnerability Cheat Sheet

A field guide for **auditing** code — yours or someone else's — for the vuln
classes that actually cause breaches. For each: **what it is → where it hides →
how to detect (grep + review questions) → how to fix**. Examples span
Postgres / Deno / TypeScript / Dart, but the review questions are language-agnostic.

> Companion: [SECURE_CLEAN_CODE_CHEATSHEET.md](SECURE_CLEAN_CODE_CHEATSHEET.md)
> (how to *write* it safely). This doc is how to *break/verify* it.

---

## How to run an audit (the workflow)

1. **Map the attack surface** — every input: HTTP routes, function args, form
   fields, file uploads, query params, headers, cookies, webhooks, deep links,
   env, DB rows that came from users.
2. **Follow the taint** — for each input, trace it to a *sink* (SQL, shell, HTML,
   file path, redirect, deserializer, template). Untrusted data reaching a
   dangerous sink without validation/escaping = a finding.
3. **Check the guards** — authn, authz, validation, output encoding, rate limits.
   Ask "what stops me from calling this directly with forged input?"
4. **Assume the client is the attacker** — ignore the UI; test the API.
5. **Rank by impact × exploitability**, write repro steps, propose the fix.
6. **Re-test after the fix**; add a regression test.

Priority order when time is short: **AuthZ (access control) → Injection →
Auth/session → Secrets → File upload/SSRF → everything else.** Broken access
control and injection are consistently the highest-impact findings.

---

## 1. Injection — SQL / NoSQL

**What:** untrusted input concatenated into a query changes its *structure*,
letting an attacker read/modify/delete data or bypass auth.

**Where it hides:** string-built SQL, dynamic `ORDER BY`/table names, `LIKE`
patterns, search filters, `IN (...)` lists, raw query escape hatches
(`knex.raw`, `sequelize.query`, `.rpc` with string interpolation, `EXECUTE` in
plpgsql).

**Detect:**
```bash
grep -RInE "execute\(|query\(|raw\(|\\$\{.*\}.*(select|insert|update|delete)" src/
grep -RInE "EXECUTE .*\|\||format\(" supabase/   # dynamic SQL in plpgsql
```
Review questions: Is any query built with `+`, template literals, or `format()`?
Does a `SECURITY DEFINER` plpgsql function build SQL from an argument? Is
`search_path` pinned?

**Fix:** **parameterize — always.** Never concatenate.
```ts
// DON'T
db.query(`select * from users where name = '${name}'`);
// DO
db.query("select * from users where name = $1", [name]);
```
```sql
-- Dynamic identifiers (table/column) can't be parameters → allowlist them,
-- and quote with format():  %I = identifier, %L = literal
execute format('select * from %I where id = $1', allowlisted_table) using p_id;
```
- Use the ORM/query-builder's bound parameters; treat `raw()` as a red flag.
- In Postgres functions: `set search_path = ''`, fully-qualify names, `%I`/`%L`.
- **NoSQL:** reject operator objects where you expect a scalar
  (`{ "$ne": null }` as a password → auth bypass). Validate types.

---

## 2. Injection — OS command / RCE

**What:** untrusted input reaches a shell/exec, running attacker commands =
**Remote Code Execution**, the worst class.

**Where it hides:** `exec`, `spawn`, `system`, `child_process`, `Deno.Command`,
`eval`, dynamic `require`/`import(userInput)`, template engines with code,
image/PDF/video shellouts (ImageMagick, ffmpeg, ghostscript), archive
extractors, `pickle`/`yaml.load`, server-side `Function()` construction.

**Detect:**
```bash
grep -RInE "exec\(|execSync|spawn\(|child_process|Deno\.Command|eval\(|new Function|vm\.runIn" src/
grep -RInE "import\(|require\(" src/ | grep -vE "['\"]"   # dynamic module path
```
Review questions: Does any shell command include a variable? Is `eval`/`Function`
ever fed data? Do you pass user input as a *filename/arg* to an external tool?

**Fix:**
- **Don't shell out.** Prefer a library API over spawning a process.
- If you must exec: **use the argv array form, never a shell string**, and
  **allowlist** the binary + args; never interpolate user data into the command.
  ```ts
  // DON'T:  new Deno.Command("sh", { args: ["-c", `convert ${file} out.png`] })
  // DO:     new Deno.Command("convert", { args: [safePath, "out.png"] })  // no shell
  ```
- **Never `eval`/`new Function`/`vm` on any data.** There is almost always a
  parser (`JSON.parse`) that does what you actually need.
- **No dynamic `import()`/`require()` from user input.** Map to a static
  allowlist of modules.
- Pin/patch the native tools you shell to (they have their own RCE CVEs), run
  them sandboxed with least privilege.

---

## 3. Cross-Site Scripting (XSS)

**What:** attacker HTML/JS runs in a victim's browser → session theft, actions
as the victim, defacement. Types: **stored** (persisted), **reflected** (in the
response to a crafted request), **DOM** (client JS writes untrusted data to a
sink).

**Where it hides:** `innerHTML`, `outerHTML`, `document.write`,
`dangerouslySetInnerHTML`, `v-html`, `insertAdjacentHTML`, `element.setAttribute`
with `href`/`src`/`on*`, `eval`, template strings rendered as HTML,
Markdown→HTML, `javascript:` URLs, unescaped server templates. In Flutter web:
`Html`/`WebView` rendering untrusted content, `Uri` built from user input.

**Detect:**
```bash
grep -RInE "innerHTML|outerHTML|document\.write|dangerouslySetInnerHTML|v-html|insertAdjacentHTML" src/
grep -RInE "href\s*=\s*.*(user|input|param)|javascript:" src/
```
Review questions: Where does user data reach the DOM as *markup* (not text)? Is
any URL/attribute built from input? Is there a Content-Security-Policy?

**Fix:**
- **Output-encode for the context** (HTML body vs. attribute vs. JS vs. URL vs.
  CSS). Let the framework escape by default:
  ```jsx
  <div>{userInput}</div>          // React escapes — safe
  // avoid dangerouslySetInnerHTML unless you sanitize first
  ```
- **Never build HTML by string concat.** Use text nodes / templating that
  auto-escapes. `el.textContent = data` is safe; `el.innerHTML = data` is not.
- **Sanitize rich HTML with a vetted library** (DOMPurify) when you truly must
  render user HTML — allowlist tags/attrs, strip `on*`, `javascript:`, `data:`.
- **Validate URLs**: allow only `https:`/`mailto:` schemes; reject
  `javascript:`/`data:`; block open redirects (§13).
- **Ship a strict Content-Security-Policy** (`default-src 'self'`, no
  `unsafe-inline`) — turns many XSS bugs into non-events.
- Set cookies `HttpOnly` + `Secure` + `SameSite` so stolen script can't read them.

---

## 4. File upload

**What:** malicious files → RCE (web-shell), XSS (HTML/SVG), path traversal
(overwrite), DoS (zip bomb / huge file), or malware distribution.

**Where it hides:** any upload endpoint, avatar/import features, storage buckets
with public write, filenames used as paths, content-type trusted from the client.

**Detect:** find upload handlers; check whether they trust `filename`,
`Content-Type`, or extension from the client, and where the file is stored/served.

**Fix (defense in depth):**
- **Allowlist extension *and* verify real content type** (magic-byte sniff), not
  the client-supplied MIME.
- **Generate your own random filename**; never use the client's. Strip the path —
  keep only a sanitized basename; reject `..`, `/`, `\`, null bytes, control
  chars.
- **Store outside the web root / in object storage**, and **serve with
  `Content-Disposition: attachment` + a fixed safe `Content-Type`** so it's
  downloaded, not executed/rendered. Never serve uploads from a path that can
  execute code.
- **SVG is active content** — treat it as HTML (sanitize or force download);
  don't inline user SVG.
- **Cap size; enforce a timeout; guard decompression** (zip/image bombs — limit
  output size and ratio).
- **Scan for malware** if files are shared with others.
- Re-encode images through a trusted library to strip embedded payloads/EXIF.
- Never let the uploader set the storage path/key directly (→ overwrite / IDOR).

---

## 5. Path traversal / LFI

**What:** `../../etc/passwd` style input escapes the intended directory to
read/write arbitrary files.

**Where it hides:** file reads/writes using a name/path from input, template
loaders, "download this report?name=..." endpoints, archive extraction (zip-slip),
static file servers.

**Detect:**
```bash
grep -RInE "readFile|writeFile|createReadStream|open\(|sendFile|path\.join\(.*req" src/
```
Review questions: Is a filesystem path ever built from input? Is the result
confined to a base dir *after* normalization?

**Fix:**
```ts
const base = "/srv/reports";
const resolved = path.resolve(base, path.normalize(userName));
if (!resolved.startsWith(base + path.sep)) throw new Error("path escape");
```
- **Canonicalize, then verify the resolved path is inside the allowed root.**
- Prefer an **allowlist / id→path map** over accepting raw paths.
- Reject `..`, absolute paths, null bytes, and symlinks that leave the root.
- Zip extraction: validate each entry's resolved target is under the dest dir.

---

## 6. Server-Side Request Forgery (SSRF)

**What:** you fetch a URL the attacker controls → they reach your internal
network, cloud metadata (`169.254.169.254` → credentials), or localhost admin.

**Where it hides:** "fetch by URL", webhooks, link previews/unfurls, image
proxies, PDF/HTML renderers, importers, any `fetch(userProvidedUrl)`.

**Detect:**
```bash
grep -RInE "fetch\(|axios|http\.get|got\(|urllib|curl|Deno\.readTextFile.*http" src/ | grep -iE "req|input|url|param"
```

**Fix:**
- **Allowlist destinations** (schemes = https only; host in an approved set).
- **Resolve DNS and block private/link-local/loopback ranges** (`10/8`,
  `172.16/12`, `192.168/16`, `127/8`, `169.254/16`, `::1`, IPv6 ULA) — and
  re-check after redirects (guard against DNS-rebinding + redirect-to-internal).
- **Disable or bound redirects**; don't follow to a new host.
- **No raw responses/errors back to the client** (blind SSRF still leaks via
  timing/size — minimize).
- Put egress behind a proxy with an allowlist for anything user-triggered.

---

## 7. Broken access control / IDOR *(usually the #1 finding)*

**What:** a user reaches data/actions that aren't theirs — by changing an id
(IDOR), calling an endpoint the UI hides, or escalating role. Includes missing
function-level authz and **mass assignment** (setting fields you shouldn't).

**Where it hides:** endpoints that take a resource `id` and don't check
ownership; "admin" routes guarded only by a hidden button; updates that accept a
whole object (`role`, `is_active`, `owner_id` slip in); RLS assumed but not
enabled; permission derived from the wrong scope (see §6 of the companion doc).

**Detect:**
```bash
grep -RInE "params\.id|body\.userId|req\.query\.id" src/   # id from client → used in query?
```
Review questions: For every id from the client — is ownership/permission
re-checked server-side? Can I call this with someone else's id? Every table has
RLS on? Any update that trusts client-supplied privilege fields?

**Fix:**
- **Authorize every request server-side, per object** — "can *this* caller do
  *this* action on *this* resource?" Never rely on the UI hiding it.
- **Scope queries to the caller** (`where owner_id = $currentUser`) and/or enforce
  **RLS**; don't fetch-then-filter-in-app (leaks via timing/errors).
- **Allowlist updatable fields** (§7 companion) — reject `role`, `is_active`,
  `owner_id`, `must_change_password` from the body (mass-assignment defense).
- **Deny by default**; new routes are locked until explicitly permitted.
- **Use unguessable ids** (UUID/ULID) as defense-in-depth, *not* as the only
  control.
- Re-derive the caller's identity/permissions from their **token**, never from a
  body/header field.

---

## 8. Authentication & session

**What:** weak login, credential stuffing, session fixation/hijack, user
enumeration, missing re-auth on sensitive ops.

**Where it hides:** login/reset/change-password flows, JWT verification toggles,
"remember me", password rules, error messages that reveal account existence.

**Fix:**
- **Keep server-side token/JWT verification ON**; verify signature, `exp`,
  audience/issuer. Never disable it to "make it work."
- **Generic auth errors** — never reveal which of user/password was wrong, or
  whether the account exists (anti-enumeration). Same for reset ("if it exists,
  we sent an email").
- **Rate-limit + lockout/backoff** on login, reset, OTP, and change-password.
- **Strong password policy** (length-first: 12+; block breached passwords) and a
  slow hash (bcrypt/scrypt/argon2) — never home-rolled or fast hashes.
- **Re-authenticate before sensitive changes**; rotate session id on privilege
  change; short-lived access tokens + rotating refresh tokens.
- **Distinguish a confirmed bad password (401) from a server error (500)** so a
  transient failure isn't reported as "wrong password" (and vice-versa).
- **MFA** for admin/privileged accounts where feasible.
- Cookies: `HttpOnly` + `Secure` + `SameSite=Lax/Strict`.

---

## 9. Cryptographic failures & secrets exposure

**What:** sensitive data unprotected in transit/at rest, or secrets leaked.

**Where it hides:** hardcoded keys, secrets in git history / logs / client
bundles, HTTP endpoints, weak/rolled crypto, predictable tokens (`Math.random`),
plaintext or reversibly-"encrypted" passwords.

**Detect:**
```bash
git log -p | grep -Ei "secret|api[_-]?key|private[_-]?key|password|token|BEGIN RSA"
grep -RInE "Math\.random|md5|sha1\(|DES|ECB" src/
# run gitleaks / trufflehog over the whole history
```

**Fix:**
- **TLS everywhere**; HSTS; no secrets in URLs/query strings (they hit logs).
- **Secrets from env / secret manager only**; never in source, client, or logs;
  **rotate on any exposure**. `.env` gitignored.
- **Passwords → argon2/bcrypt/scrypt** (never reversible). Never log or return
  password material.
- **CSPRNG for anything security-relevant** (`crypto.getRandomValues` /
  `crypto.randomUUID`), never `Math.random`.
- **Modern algorithms** (AES-GCM, not ECB; SHA-256+, not MD5/SHA-1); don't
  invent crypto — use the platform library.
- Encrypt sensitive data at rest; minimize what you store (you can't leak what
  you don't keep).

---

## 10. Security misconfiguration

**What:** insecure defaults, verbose errors, open buckets, debug on in prod,
missing headers, default creds, over-broad CORS.

**Detect / review:** debug/stack traces reaching clients? CORS `*` on
authenticated APIs? Storage buckets public-write? Default admin creds? Security
headers present? Unused services/ports/routes exposed?

**Fix:**
- **Harden defaults; disable debug in prod**; generic error pages.
- **Security headers:** CSP, `X-Content-Type-Options: nosniff`, `Referrer-Policy`,
  `Strict-Transport-Security`, `X-Frame-Options`/`frame-ancestors`,
  `Permissions-Policy`, and `Cache-Control: no-store` on sensitive responses.
- **CORS: explicit origin allowlist**, not `*`, for anything credentialed.
- **Least privilege** on buckets, DB roles, cloud IAM, service accounts.
- **Remove defaults** (creds, sample routes, admin panels) before ship.
- **Reproducible, minimal images/builds**; patch the platform.

---

## 11. Vulnerable & outdated components (supply chain)

**What:** a known CVE in a dependency, or a malicious/typosquatted package.

**Detect:**
```bash
npm audit --production        # or: pnpm audit / yarn npm audit
flutter pub outdated
# CI: dependabot / renovate + osv-scanner / snyk
```

**Fix:**
- **Pin exact versions**; commit the lockfile; review dependency diffs.
- **Automate CVE alerts** (Dependabot/Renovate + OSV) and patch on a cadence.
- **Verify integrity** (lockfile hashes); prefer few, well-maintained deps.
- Beware typosquats and postinstall scripts; vet new dependencies.
- Rebuild/re-deploy after patching a runtime/base image.

---

## 12. Insecure deserialization

**What:** deserializing untrusted data instantiates objects / triggers gadgets →
RCE or tampering.

**Where it hides:** `pickle`, Java/PHP native serialization, `yaml.load` (unsafe),
`Function`/`eval` on JSON, signed-but-not-verified tokens, `.NET`
BinaryFormatter.

**Fix:**
- **Only deserialize trusted data.** For untrusted input, use **data-only
  formats** (`JSON.parse`, `yaml.safeLoad`) that can't instantiate arbitrary
  types.
- **Validate the parsed shape** against a schema (zod / manual) before use.
- **Sign + verify** any serialized state you round-trip through the client
  (HMAC), and reject on mismatch.
- Never `pickle.loads` / native-deserialize attacker bytes.

---

## 13. CSRF & open redirect

**CSRF — what:** a victim's browser is tricked into making an authenticated
state-changing request. **Fix:** `SameSite=Lax/Strict` cookies, anti-CSRF tokens
(double-submit / synchronizer) on state-changing routes, prefer bearer tokens in
headers over ambient cookies for APIs, require re-auth on the most sensitive
actions.

**Open redirect — what:** `?next=http://evil.com` bounces users to a phishing
site (and aids SSRF/OAuth token theft). **Detect:**
```bash
grep -RInE "redirect\(|res\.location|window\.location\s*=" src/ | grep -iE "req|param|next|url|return"
```
**Fix:** **allowlist redirect targets** or accept only **relative paths**
(reject anything with a scheme/host); never redirect to a raw user-supplied
absolute URL.

---

## 14. SSTI, XXE, LDAP/header/log injection (the long tail)

- **SSTI (template injection):** user input rendered *as a template*
  (`{{7*7}}`→49) → RCE. **Fix:** never build templates from input; pass input as
  *data* to a fixed template; sandbox the engine.
- **XXE (XML external entities):** malicious XML reads files / SSRF via
  `<!ENTITY>`. **Fix:** disable DTDs/external entities in the parser; prefer JSON.
- **LDAP / filter injection:** escape LDAP special chars; parameterize filters.
- **HTTP header / response splitting:** input containing `\r\n` in a header/cookie.
  **Fix:** strip CR/LF; use the framework's header API.
- **Log injection / forging:** newlines/control chars in logged input forge log
  lines. **Fix:** encode/escape untrusted data before logging; log structured
  fields, not concatenated strings.
- **CRLF / email header injection** in mail features: sanitize address/subject.

---

## 15. Rate limiting, resource exhaustion & DoS

- **Rate-limit** auth, search, upload, and any expensive endpoint (per-IP +
  per-account).
- **Bound everything:** request body size, array lengths, page sizes, query
  complexity, upload size, regex input (guard against **ReDoS** —
  catastrophic-backtracking patterns on user input), decompression ratios.
- **Timeouts** on all outbound calls and long operations; **pagination** on list
  endpoints (no unbounded `select *`).
- **Idempotency keys** on create/payment-like actions to survive retries safely.

---

## 16. Logging, monitoring & auditability

- **Log security events** (authn failures, authz denials, admin actions, password
  changes) as structured **audit records** — enough to reconstruct "who did what
  when," without secrets/PII.
- **Never log** passwords, tokens, keys, session ids, internal/synthetic emails,
  full PII, OTPs (see companion §9).
- **Alert** on spikes in failures/denials, new admin actions, config changes.
- **Protect log integrity** (append-only/exportable); attackers delete logs.
- **Include a correlation id** so a generic client error maps to a detailed
  server record.

---

## 17. Mobile / Flutter-specific

- **No secrets in the app binary** — anything shipped is extractable; move
  privileged actions server-side. Only publishable/anon keys client-side.
- **Secure local storage:** tokens/PII in the platform keystore
  (`flutter_secure_storage`), not `SharedPreferences`/plaintext.
- **Certificate pinning** for high-value APIs; always TLS; reject bad certs
  (never disable verification).
- **Deep links / intents are untrusted input** — validate params, don't
  auto-execute privileged actions from a link.
- **WebViews:** disable JS unless needed; never load untrusted HTML; restrict
  `javascript:`/file access; validate `postMessage` origins.
- **Reduce leakage:** obscure sensitive screens in the app switcher, disable
  verbose logging in release, clear clipboard for sensitive copies.
- **Don't trust the client clock, client validation, or client-set ids.**

---

## OWASP Top 10 (2021) — quick map to sections above

| # | Category | See |
|---|---|---|
| A01 | **Broken Access Control** | §7 (IDOR, mass-assignment, RLS), companion §6 |
| A02 | **Cryptographic Failures** | §9 |
| A03 | **Injection** (SQL, cmd/RCE, XSS) | §1, §2, §3, §14 |
| A04 | **Insecure Design** | whole companion doc — threat-model early, fail-closed |
| A05 | **Security Misconfiguration** | §10 (+ headers, CORS, XXE §14) |
| A06 | **Vulnerable/Outdated Components** | §11 |
| A07 | **Identification & Auth Failures** | §8 |
| A08 | **Software & Data Integrity Failures** | §12 (deser.), §11 (supply chain) |
| A09 | **Security Logging & Monitoring Failures** | §16 |
| A10 | **Server-Side Request Forgery (SSRF)** | §6 |

## OWASP API Security Top 10 (2023) — extra API-focused checks

- **API1 Broken Object-Level Authorization (BOLA/IDOR)** → §7 (per-object authz).
- **API2 Broken Authentication** → §8.
- **API3 Broken Object *Property* Level Authorization** → §7 (mass assignment +
  excessive data exposure: return only needed fields).
- **API4 Unrestricted Resource Consumption** → §15.
- **API5 Broken Function-Level Authorization** → §7 (guard every function/route).
- **API6 Unrestricted Access to Sensitive Business Flows** → rate-limit/abuse-proof
  flows (bulk buy, invite, export).
- **API7 SSRF** → §6.
- **API8 Security Misconfiguration** → §10.
- **API9 Improper Inventory Management** → document every endpoint/version;
  retire old/undocumented ones (shadow APIs).
- **API10 Unsafe Consumption of 3rd-party APIs** → validate/timeout/rate-limit
  data *from* upstreams too; don't blindly trust their responses.

---

## OWASP Mobile Top 10 (2024) — pointers

Improper Credential Usage, Inadequate Supply-Chain Security, Insecure
Auth/Authz, Insufficient Input/Output Validation, Insecure Communication,
Inadequate Privacy Controls, Insufficient Binary Protections, Security
Misconfiguration, Insecure Data Storage, Insufficient Cryptography →
all covered by §17 + the relevant server-side sections.

---

## One-screen audit checklist

```
ACCESS CONTROL
[ ] Every endpoint authorizes per-object, server-side (not UI-gated).
[ ] Client ids re-checked for ownership; can't swap to another user's id.
[ ] Updates allowlist fields; role/is_active/owner_id rejected from body.
[ ] RLS enabled on every data table; deny-by-default.

INJECTION
[ ] All SQL parameterized; no string-built queries; dynamic identifiers allowlisted.
[ ] No shell string exec / eval / Function / dynamic import on any input.
[ ] User data reaching the DOM is text or sanitized; CSP present.
[ ] File paths canonicalized + confined; URLs (fetch/redirect) allowlisted.

AUTH & SECRETS
[ ] JWT/token verification ON; generic auth errors; rate-limited; slow hash.
[ ] Re-auth on sensitive changes; 401(bad pw) ≠ 500(server error).
[ ] No secret in source/history/logs/client; CSPRNG; TLS; secrets rotated.

UPLOAD / SSRF / DESER
[ ] Uploads: content-type verified, random name, stored inert, size-capped, SVG inert.
[ ] Outbound fetch allowlisted; private/metadata IPs blocked; redirects bounded.
[ ] Only JSON/safe-load on untrusted data; parsed shape schema-validated.

CONFIG / DEPS / LOGGING
[ ] Debug off in prod; security headers set; CORS not '*'; buckets least-priv.
[ ] Deps pinned + CVE-scanned; lockfile committed.
[ ] Security events audited; no secrets/PII logged; alerts on anomalies.

LIMITS
[ ] Body/array/page/upload sizes bounded; timeouts; pagination; ReDoS-safe regex.
```

---

*Companion:* [SECURE_CLEAN_CODE_CHEATSHEET.md](SECURE_CLEAN_CODE_CHEATSHEET.md).
*These are guidelines, not a guarantee — pair them with dependency scanning,
SAST/DAST, and, for anything high-stakes, a professional penetration test.*
