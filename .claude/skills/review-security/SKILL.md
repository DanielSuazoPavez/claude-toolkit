---
name: review-security
description: Targeted security audit of specific files or modules. Use when requests mention "security review", "vulnerability check", "security audit", "attack surface", or "pen test review".
argument-hint: File paths, module names, or leave empty for recent changes
---

Use for on-demand security review of specific files or modules. Complements CC's built-in `/security-review` (PR-level diffs) by supporting targeted, pre-commit, and existing-code audits.

**See also:** `/review-changes` (general code review), `code-reviewer` agent (structural quality), CC's `/security-review` (PR-level security review)

## When to Use

- Security-sensitive code before committing (auth, payments, user input handling)
- Auditing existing modules not covered by a PR diff
- After adding a new external-facing endpoint or data flow
- When code-reviewer flags a security concern worth deeper analysis

## Process

### Phase 0: Scope and Context

1. **Determine target files**: If `$ARGUMENTS` provided, use those. Otherwise, review uncommitted changes (`git diff --name-only HEAD`).
2. **Identify the trust boundary**: Is this code internet-facing? Internal API? CLI tool? Background job? This determines severity calibration.
3. **Read project security patterns**: Check for existing sanitization helpers, auth middleware, validation layers, ORM usage. Don't flag what's already defended.

```
Trust boundary → severity calibration:
├─ Internet-facing (web API, form handler)     → Strict
├─ Authenticated internal API                  → Moderate
├─ Internal service-to-service                 → Moderate-low
├─ CLI tool / local script                     → Low
└─ Test files                                  → Skip (out of scope)
```

### Phase 1: Trace Data Flow

For each input source (request params, file reads, env vars, DB results, external API responses):

1. **Identify entry points** — where does untrusted data enter?
2. **Trace through transformations** — is it sanitized, validated, escaped before use?
3. **Identify sinks** — where does it end up? (SQL query, shell command, HTML output, file path, redirect URL, deserialization)
4. **Check defense** — is there a control between entry and sink? Is it the right control for this sink type?

```
Entry → [transform?] → [validation?] → [sanitization?] → Sink
                                                           │
                                              Is the defense sufficient
                                              for THIS sink type?
                                              ├─ Yes → Not a finding
                                              └─ No  → Finding
```

**Critical**: Trace the actual code path. Don't flag "missing validation" if validation happens in middleware, a decorator, or a caller. Read the defense before claiming it's absent.

### Phase 2: Check Vulnerability Domains

Work through each domain systematically. See `resources/DOMAINS.md` for detailed patterns, but the core checks are:

| Domain | What to look for |
|--------|-----------------|
| **Injection** | User input reaching SQL, shell, template, LDAP, or eval sinks without parameterization/escaping |
| **Auth/Authz** | Missing auth checks on endpoints, privilege escalation paths, broken access control, JWT misuse |
| **Secrets** | Hardcoded credentials, secrets in logs/errors, API keys in client-side code |
| **Input validation** | Type confusion, boundary violations, path traversal, open redirects |
| **Crypto** | Weak algorithms (MD5/SHA1 for security), static IVs, timing-unsafe comparisons, custom crypto |
| **Data exposure** | Sensitive data in error messages, verbose stack traces in production, PII in logs |
| **SSRF/CSRF** | User-controlled URLs fetched server-side, state-changing GETs without CSRF tokens |
| **Deserialization** | Untrusted data passed to pickle, YAML.load, unserialize, JSON.parse with reviver |

### Phase 3: Filter False Positives

Before reporting any finding, run it through these filters:

**Hard exclusions** (never report):
- Framework-provided protections that are active (ORM parameterized queries, React JSX escaping, Django CSRF middleware)
- DoS/resource exhaustion (out of scope — that's infrastructure)
- Theoretical race conditions without a concrete exploit path
- Missing hardening vs. actual vulnerabilities (e.g., missing rate limiting is not a vulnerability)
- Test files
- Environment variables (treated as trusted unless the review scope is infrastructure)

**Calibration checks** (before assigning severity):
- Would this require an authenticated attacker? → Lower severity unless auth bypass is also present
- Is the vulnerable code reachable from an external input? → If not, Info at most
- Does the framework/language prevent this by default? → Verify the protection is actually active, then exclude

**The 80% rule**: Only report findings where you're >80% confident the vulnerability is exploitable given the codebase context. "This could theoretically be a problem" is not a finding.

## Rationalizations

| Rationalization | Counter |
|-----------------|---------|
| "The code looks safe, no need to trace data flow" | Looking safe and being safe are different. Trace from entry to sink — every time. |
| "This is just an internal tool" | Internal tools get compromised. Check the trust boundary, calibrate severity, but still review. |
| "The framework handles this" | Which framework feature? Is it enabled? Is it configured correctly? Verify, don't assume. |
| "I should flag everything to be thorough" | False positives erode trust. Use the 80% rule. Report what's exploitable, not what's theoretically possible. |
| "I already checked a similar pattern earlier" | Each call site has different context. The same function is safe in one caller, vulnerable in another. |
| "Too many files to review carefully" | Prioritize by trust boundary. Internet-facing code first, then auth, then internal. Skip test files. |

## Output Format

```markdown
# Security Review: [Scope]

**Trust boundary**: [Internet-facing / Internal API / CLI / etc.]
**Files reviewed**: [count]

---

## Findings

### [CRITICAL/HIGH/MEDIUM] #1: [Category]: `file.py:line`

**Vulnerability**: [What's wrong — one sentence]

**Data flow**:
```
[entry point] → [transforms] → [vulnerable sink]
```

**Exploit scenario**: [Concrete attack — not theoretical. "An attacker could..." with specific input]

**Fix**: [Specific recommendation — parameterize, escape, validate, add auth check]

---

## Summary

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 0 |
| Medium | 0 |
| Info | 0 |

**Verdict**: PASS | FINDINGS | CRITICAL

[1-2 sentences: overall security posture of reviewed code]
```

If no findings:

```markdown
# Security Review: [Scope]

**Trust boundary**: [level]
**Files reviewed**: [count]

**Verdict**: PASS

No exploitable vulnerabilities identified. [Brief note on what was checked]
```

## Severity Definitions

| Severity | Criteria |
|----------|----------|
| **Critical** | Exploitable by unauthenticated attacker, leads to RCE, data breach, or full auth bypass |
| **High** | Exploitable with some access, leads to privilege escalation, significant data exposure, or injection |
| **Medium** | Requires specific conditions, leads to limited data exposure, CSRF, or information leakage |
| **Info** | Defense-in-depth suggestion, not exploitable in current context but worth noting for future changes |

## Worked Example

Target: a Flask endpoint handling user profile updates.

```python
# routes/profile.py
@app.route("/profile/<user_id>", methods=["POST"])
@login_required
def update_profile(user_id):
    data = request.get_json()
    db.execute(f"UPDATE users SET name = '{data['name']}' WHERE id = {user_id}")
    avatar_path = f"uploads/{data['avatar_filename']}"
    with open(avatar_path, "wb") as f:
        f.write(request.files["avatar"].read())
    return jsonify({"status": "ok"})
```

**Phase 0**: Internet-facing (web API behind `@login_required`) → Strict calibration.

**Phase 1 — Trace**:
- `data['name']` → string interpolation → SQL query (sink: SQL)
- `user_id` → from URL path → SQL WHERE clause (sink: SQL)
- `data['avatar_filename']` → string concat → `open()` file path (sink: filesystem)

**Phase 2 — Findings**:

**HIGH #1: Injection: `routes/profile.py:5`**
`data['name']` → f-string → SQL. No parameterization.
```
request.get_json()['name'] → f-string interpolation → db.execute()
```
Fix: `db.execute("UPDATE users SET name = ? WHERE id = ?", (data['name'], user_id))`

**HIGH #2: Injection: `routes/profile.py:5`**
`user_id` from URL also interpolated into SQL. Plus no check that `user_id == current_user.id` (IDOR).
Fix: Parameterize AND verify `user_id` matches authenticated user.

**MEDIUM #3: Input validation: `routes/profile.py:6`**
`data['avatar_filename']` reaches `open()` — path traversal via `../../etc/cron.d/backdoor`.
Fix: `pathlib.Path(filename).name` to strip directory components, or use a generated filename.

**Filtered out** (not reported):
- "Missing CSRF protection" → Flask-WTF CSRF is a framework concern, and this is a JSON API using token auth, not cookies. Hard exclusion.
- "No rate limiting" → Missing hardening, not a vulnerability. Hard exclusion.

## Anti-Patterns

| Pattern | Problem | Fix |
|---------|---------|-----|
| **Checklist without tracing** | Flags "no input validation" without checking if validation happens elsewhere | Trace entry → sink before flagging |
| **Framework ignorance** | Flags SQL injection when ORM with parameterized queries is in use | Read the query construction — is it parameterized? |
| **Severity inflation** | Everything is "Critical" | Apply trust boundary calibration and severity definitions |
| **Narrative findings** | Paragraphs of explanation without actionable structure | Use the output format — data flow, exploit scenario, fix |
| **Theoretical attacks** | "An attacker could theoretically..." | Show the concrete input and code path, or don't report it |
