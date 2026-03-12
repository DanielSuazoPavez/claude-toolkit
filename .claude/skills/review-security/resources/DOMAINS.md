# Security Vulnerability Domains

Detailed patterns for each vulnerability domain. Reference during Phase 2 of the review process.

## 1. Injection

**Sinks to check**: SQL queries, shell commands, template engines, LDAP queries, eval/exec, regex from user input.

| Language/Framework | Safe | Vulnerable |
|-------------------|------|------------|
| Python/SQLAlchemy | `session.query(User).filter(User.id == user_id)` | `session.execute(f"SELECT * FROM users WHERE id = {user_id}")` |
| Python/subprocess | `subprocess.run(["ls", "-la", path])` (list form) | `subprocess.run(f"ls -la {path}", shell=True)` |
| Node/SQL | `db.query("SELECT * FROM users WHERE id = $1", [id])` | `` db.query(`SELECT * FROM users WHERE id = ${id}`) `` |
| Django ORM | `User.objects.filter(id=user_id)` | `User.objects.raw(f"SELECT * FROM users WHERE id = {user_id}")` |
| Go/database/sql | `db.Query("SELECT * FROM users WHERE id = ?", id)` | `db.Query("SELECT * FROM users WHERE id = " + id)` |

**Key insight**: String concatenation/interpolation into query strings is the pattern. Parameterized queries are the fix. ORMs are safe *unless* raw queries are used.

## 2. Auth/Authz

**What to check**:
- Every route/endpoint: is there an auth decorator/middleware? Is it the right one?
- Object-level access: does the query filter by the authenticated user's ID?
- Role checks: is the role check on the server, not just the client?
- JWT: is the signature verified? Is `alg: none` rejected? Is expiry checked?

**Common patterns**:
- Endpoint missing `@login_required` / `@authenticate` decorator
- Query fetches by ID without filtering by `owner_id` (IDOR)
- Admin endpoint checks role in frontend but not backend
- JWT verified but claims not validated (expired tokens accepted)

## 3. Secrets Exposure

**Where secrets leak**:
- Hardcoded in source: API keys, passwords, tokens in code or config committed to git
- Error messages: stack traces with connection strings, full SQL with credentials
- Logs: request/response bodies containing tokens, session IDs, passwords
- Client-side: API keys in JavaScript bundles, secrets in HTML source

**Not a finding**: Secrets in environment variables (treated as trusted), secrets in `.env` files that are gitignored, example/placeholder values (`sk-test-xxxx`).

## 4. Input Validation

**Beyond injection** — validation issues that don't involve a sink:
- **Path traversal**: `../../etc/passwd` in file paths — check for `..` normalization
- **Open redirect**: User-controlled redirect URL without allowlist — `redirect_to=https://evil.com`
- **Type confusion**: Expected integer, got string/array — does the code handle it?
- **Boundary violations**: Array index from user input without bounds check
- **ReDoS**: User-controlled regex or input to complex regex — catastrophic backtracking

## 5. Cryptography

| Issue | What to look for |
|-------|-----------------|
| Weak hashing | MD5, SHA1 for passwords or security tokens. SHA256+ or bcrypt/argon2 for passwords |
| Static IV | Hardcoded initialization vectors in encryption. IVs must be random per operation |
| Timing attacks | String comparison for secrets (`==` instead of `hmac.compare_digest` / `crypto.timingSafeEqual`) |
| Custom crypto | Any hand-rolled encryption. Always use established libraries |
| Insecure random | `Math.random()`, `random.random()` for security tokens. Use `crypto.randomBytes` / `secrets.token_hex` |

## 6. Data Exposure

**Error handling**:
- Production code returning full stack traces
- Database errors with table/column names exposed to users
- Verbose error messages revealing internal paths or versions

**Logging**:
- Request bodies logged without PII redaction
- Auth tokens or session IDs in log output
- User passwords logged during auth failures

## 7. SSRF / CSRF

**SSRF**: User controls a URL that the server fetches.
- Check: Is there an allowlist of permitted domains/IPs?
- Check: Can the attacker reach internal services (169.254.169.254, localhost, internal DNS)?
- Not a finding: URL is constructed server-side with only a path segment from user input (unless path traversal applies)

**CSRF**: State-changing operation without CSRF protection.
- Check: Does the framework provide CSRF middleware? Is it enabled?
- Check: Are state-changing operations on POST/PUT/DELETE (not GET)?
- Not a finding: API-only backends using token auth (CSRF is cookie-specific)

## 8. Deserialization

**Dangerous deserializers** (untrusted input → code execution):

| Language | Dangerous | Safe alternative |
|----------|-----------|-----------------|
| Python | `pickle.loads()`, `yaml.load()` (without Loader) | `json.loads()`, `yaml.safe_load()` |
| PHP | `unserialize()` | `json_decode()` |
| Java | `ObjectInputStream.readObject()` | JSON/protobuf deserialization |
| Ruby | `Marshal.load()`, `YAML.load()` | `JSON.parse()`, `YAML.safe_load()` |
| Node | `node-serialize`, `js-yaml.load()` (schema: DEFAULT_FULL) | `JSON.parse()`, `js-yaml.load()` (default safe since v4) |

**Key insight**: If untrusted data reaches any of these deserializers, it's likely Critical. The fix is always: use a safe format (JSON) or safe loader.
