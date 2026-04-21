# v3 Audit — `.claude/skills/` (Code Quality subset)

Exhaustive file-level audit of the 3 skills in the Code Quality category (per `docs/indexes/SKILLS.md`).

**Finding tags:** `Keep` · `Rewrite` · `Defer` · `Investigate`
**Audit question:** does this shape assume orchestration, or is it workshop-shaped?

Skills audited: `refactor`, `review-security`, `design-tests` (including `resources/` subdirectories).

---

## Summary

Three skills, three different output shapes — and that difference is the most interesting finding of the subset:

| Skill | Output mode | Rationale |
|-------|-------------|-----------|
| `refactor` | **Saves** analysis doc to `output/claude-toolkit/analysis/...` | Analysis IS the deliverable — user decides later whether to act |
| `review-security` | **Inline** findings presented to user | Findings are acted on immediately or dismissed; a saved file would accumulate stale audits |
| `design-tests` | **Inline** guidance + audit-mode gap report (inline markdown, no file) | Test patterns are read-and-apply; gap audits get eyeballed, not archived |

All three are workshop-shaped: the skill runs in a consumer session, reads the consumer's code, returns findings. No orchestration leakage.

**Four classes of finding** emerge:

1. **`type:` frontmatter field — 1 instance.** Only `design-tests` carries `type: knowledge` (line 3). Workflow subset flagged 4 instances. The repo-wide sweep (workflow queue item 7: move to `metadata.type`) picks this up.

2. **`See also` cross-references to `/brainstorm-idea` — 3 instances in `refactor`.** Lines 47 (*"flag that `/brainstorm-idea` may be needed first"*), 105 (*"escalate to `/brainstorm-idea`"*), 210 (See also list). Per workflow queue item 3, `/brainstorm-idea` is being renamed to `/brainstorm-feature` (software design doc). The refactor skill's references are exactly to that sense — architectural-issue escalation goes to the software-design skill. So after rename, all three occurrences should update to `/brainstorm-feature`. No semantic change, just a rename lockstep.

3. **`code-reviewer` agent references — 4 instances across all 3 skills.** `refactor` lines 104, 106, 211; `review-security` lines 10, 17; `design-tests` line 394. Per agents audit queue items 1-2, `code-reviewer` is being flipped from opus → sonnet (structured checklist work). No skill-text changes needed — the agent continues to exist, just runs on a different model. Cross-reference noted.

4. **Duplicate / scope overlap: `review-security` vs CC's `/security-review`.** The skill explicitly frames itself as a complement (*"Complements CC's built-in `/security-review` (PR-level diffs) by supporting targeted, pre-commit, and existing-code audits"* — line 8). That's the right framing and it's surfaced in both the description header and the See also. No drift — but see Investigate below on whether the complement is actually getting used.

Plus one scope-of-applicability observation noted in the cross-cutting section: `review-security` correctly de-scopes infrastructure-level concerns (DoS, rate limiting) in Phase 3.

**User resolutions surfaced during review:**
- **`review-security` has never been invoked in the wild** (to user's knowledge). The skill is well-shaped, but well-shaped ≠ worth keeping if nobody calls it. Same diagnostic posture as `pattern-finder` in the agents audit (queue item 8): check invocation frequency before deciding between (a) keep, (b) sharpen discovery/description so it surfaces when needed, or (c) deprecate. CC's built-in `/security-review` may already cover enough of the surface that the complement isn't earning its context cost.
- **`design-tests` Python-centricity is an accepted scope, not a future concern.** The skill is explicitly pytest/Python — that's the declared lane, not a gap waiting to be filled. No parallel skill for other languages is queued.

Findings below: 1 Investigate (review-security — usage-worthyness diagnostic), 1 Rewrite (design-tests `type:` sweep — picked up by repo-wide move), 1 Keep (refactor with rename-lockstep).

---

## Files

### `refactor/SKILL.md`

- **Tag:** `Keep` (content — rename-lockstep only when brainstorm pair ships)
- **Finding:** Analysis-document-producing skill. Triage-first approach (Cosmetic / Structural / Architectural) prevents the "refactoring for its own sake" anti-pattern — the Cosmetic branch explicitly short-circuits to *"Stop here — not worth the ceremony."* That's the right guard.

  Five-Lens framework (Coupling / Cohesion / Dependency Direction / API Surface / Shared Patterns) is well-calibrated. Lens 5 (Shared Patterns) has an explicit threshold (*"3+ occurrences, or 2 with high complexity. Two simple similar blocks is NOT a signal — premature abstraction adds coupling and indirection for no gain"*) — that's the exact anti-abstraction stance the code-style conventions doc endorses.

  **Output path is correct.** Line 95: `output/claude-toolkit/analysis/{YYYYMMDD}_{HHMM}__refactor__{target}.md`. Matches the `output/claude-toolkit/` audit's canonical subdir list. No drift.

  Three worked examples (Shared Patterns, Dependency Direction, Cohesion) are excellent — each shows the lens's *signal*, not just the verdict. The Cohesion example (600-line `helpers.py`) also correctly argues *"File size is NOT the problem — lack of cohesion is"* — that's a subtle distinction most refactor prompts miss.

  Anti-patterns and Rationalizations tables are tight. "Premature extraction" rationalization counter (*"Wait for 3+ occurrences or 2 with high complexity"*) pairs with the Shared Patterns lens threshold — consistent.

  No frontmatter drift (no `type:` field). `allowed-tools: Read, Grep, Glob, Write` — correct and minimal (Write is needed for the analysis doc).

  **Cross-audit thread: `/brainstorm-idea` references at lines 47, 105, 210.** All three reference the *software-design* sense (architectural issues escalate to design exploration). Per workflow queue item 3, `/brainstorm-idea` is being renamed to `/brainstorm-feature`. After that rename lands, these three occurrences update in lockstep. Semantic stays; name changes.

  **Cross-audit thread: `code-reviewer` references at lines 104, 106, 211.** Per agents queue items 1-2, model flips opus → sonnet. No skill-text change needed.

  Workshop-shaped: reads consumer's code, writes analysis to consumer's `output/claude-toolkit/analysis/`. No orchestration.

- **Action:** at decision point (coordinated with workflow queue item 3): update three `/brainstorm-idea` references to `/brainstorm-feature` when the brainstorm rename lands. No independent changes.
- **Scope:** trivial — 3 in-place string replacements, part of the coordinated rename commit.

### `review-security/SKILL.md`

- **Tag:** `Investigate`
- **Finding:** Targeted security audit skill. Explicitly frames itself as a *complement* to CC's built-in `/security-review` (PR-level diff review) — this skill handles pre-commit / targeted / existing-code audits. The scope split is clear in line 8 and reinforced in the See also block. That's the right posture: don't duplicate the built-in, extend it.

  **Worthyness question — user flag.** The skill is well-shaped (see below) but to the user's knowledge has **never been invoked in the wild**. That's the load-bearing question for this entry, and it outranks any content critique: a skill that isn't called doesn't earn its context cost regardless of quality. Same diagnostic shape as `pattern-finder` in the agents audit (queue item 8): check invocation frequency first, then decide.

  Three possible resolutions once data is in hand:
  - **(a) Keep** — if invocation data shows the skill is getting called ≥ a few times and producing useful findings. Content is already solid, no rewrite needed.
  - **(b) Sharpen** — if the issue is discovery (user/Claude doesn't think of `/review-security` when they should). The description's trigger keywords (*"security review", "vulnerability check", "security audit", "attack surface", "pen test review"*) are decent but could be broadened to surface in more-security-adjacent sessions. A hook-side surfacing path (analogous to `surface-lessons.sh` / the mooted `surface-docs.sh`) could also help.
  - **(c) Deprecate** — if CC's built-in `/security-review` covers enough of the surface that the targeted/pre-commit/existing-code scope of this skill is unused in practice. The built-in handles PR-level; the marginal value of a separate skill for non-PR contexts has to be real, not theoretical.

  The rest of the content review stands regardless of the worthyness call — captured below for completeness if the decision is Keep or Sharpen.

  **Phase 0 "Trust boundary → severity calibration"** (line 28-34) is one of the strongest sections in any skill — five calibration levels (Internet-facing → Test files) with explicit severity implications. This is the part that prevents the "everything is Critical" anti-pattern the rest of the toolkit can't otherwise enforce.

  **Phase 1 "Trace Data Flow"** — *"Trace the actual code path. Don't flag 'missing validation' if validation happens in middleware, a decorator, or a caller. Read the defense before claiming it's absent"* (line 54). This is specifically calibrated against the "checklist without tracing" anti-pattern (line 212) that security reviewers (human and LLM alike) fall into.

  **Phase 3 "Filter False Positives"** — explicit hard-exclusion list (framework protections, DoS, theoretical races, missing hardening, test files, env vars) + calibration checks. The **80% rule** (*"Only report findings where you're >80% confident the vulnerability is exploitable given the codebase context"*) is the key guard against findings inflation. That's the discipline that makes the skill trustworthy in a consumer session.

  **Worked Example** (Flask endpoint, lines 165-207) is dense and pedagogically strong — shows Phase 0 (calibration), Phase 1 (three parallel traces), Phase 2 (three findings with varying severity), and Phase 3 (two filtered-out non-findings with explicit reasoning). Reads like a real review, not a toy example.

  **`resources/DOMAINS.md`** (98 lines) — detailed per-domain patterns referenced by Phase 2. Correctly subordinated: the main SKILL.md has the table of domains; DOMAINS.md has the per-language/framework vulnerable-vs-safe code snippets. `resources/` subdirectory is the correct home per `shape-proposal` / frontmatter conventions (skill-owned resources, not top-level). Good structure.

  **Output shape: inline, no file.** Findings are presented to the user, acted on or dismissed. A saved-artifact mode would be wrong here — security findings either get fixed immediately or documented in the bug tracker; stale audit files are liability, not asset. This is a deliberate shape difference from `refactor` and it's correct.

  **Cross-audit thread: `code-reviewer` references at lines 10, 17.** Per agents queue items 1-2, model flip opus → sonnet. No skill-text change needed — just noting the cross-ref.

  Tools list `Read, Grep, Glob, Bash(git diff:*), Bash(git log:*)` — correct and minimal. The Bash scoping to `git diff` / `git log` is exactly right for the "uncommitted changes" fallback scope (Phase 0 step 1).

  No frontmatter drift (no `type:` field). No output-path drift (no output path — intentional).

  Workshop-shaped: runs in consumer session, reads consumer's code, returns findings. The audit is a sanity pass over the consumer's existing defenses ("is the framework protection actually active?") — not an orchestration. Clean.

- **Action:** at decision point: (1) run invocation-frequency diagnostic (same approach as pattern-finder's queue item 8 — grep conversation history / session logs for `/review-security` calls); (2) based on data, pick Keep / Sharpen / Deprecate; (3) if Deprecate, remove skill + update `docs/indexes/SKILLS.md` + remove from distributions; (4) if Sharpen, broaden description triggers and/or consider `surface-*` hook path (coordinates with workflow queue item 6 — docs-surfacing direction). Carry-forward cross-reference noted on the `code-reviewer` model flip regardless of outcome.
- **Scope:** (1) small diagnostic. (2) decision. (3) small if deprecating (skill removal + one index + distribution cleanup). (4) moderate if sharpening.

### `review-security/resources/DOMAINS.md`

- **Tag:** `Keep`
- **Finding:** Per-domain vulnerability patterns with concrete Safe / Vulnerable code tables. Covers 8 domains (Injection, Auth/Authz, Secrets Exposure, Input Validation, Cryptography, Data Exposure, SSRF/CSRF, Deserialization) — that's the full OWASP-adjacent surface minus the infrastructure-level concerns (DoS, rate limiting) which the main skill correctly de-scopes.

  **Language/framework coverage in Injection domain**: Python/SQLAlchemy, Python/subprocess, Node/SQL, Django ORM, Go/database/sql. Deserialization table covers Python / PHP / Java / Ruby / Node with safe alternatives. That's a decent breadth for a small doc.

  **"Not a finding" annotations are present on the right sections**:
  - Secrets: *"Secrets in environment variables (treated as trusted)"* — aligns with main skill Phase 3 exclusion.
  - SSRF: *"URL is constructed server-side with only a path segment from user input (unless path traversal applies)"* — correctly scopes out the non-exploitable case.
  - CSRF: *"API-only backends using token auth (CSRF is cookie-specific)"* — the modern-API exception.

  These align with the main skill's false-positive filters. Good consistency.

  No drift. Referenced exactly once by the main skill (*"See `resources/DOMAINS.md` for detailed patterns"* — line 58) — the correct pattern for a resource file.

- **Action:** none.

### `design-tests/SKILL.md`

- **Tag:** `Rewrite` (frontmatter only — picked up by repo-wide `type:` sweep)
- **Finding:** Largest skill in the subset (397 lines) + three resource files totaling 569 lines. Scope is deliberately narrow: **Python + pytest specifically**, not "testing in general." The description (line 4) enumerates pytest-specific triggers (*"pytest", "fixtures", "mocking", "conftest", "parametrize"*) — the scoping is explicit both in the description and in implementation (every code sample is Python/pytest).

  That Python-only scoping is correct for this toolkit's current usage (the workshop itself is mixed Python + shell; `design-aws`, `design-db`, `design-docker` are all Python-adjacent). Not a drift — but worth noting for when the ecosystem adds a non-Python consumer.

  **Decision-tree entry at "What Are You Doing?"** (line 13-29) correctly routes to the right resource:
  - Greenfield → `resources/QA_STRATEGY.md` for planning
  - Audit mode → `QA_STRATEGY.md` + Audit Mode below
  - Adding tests → Test Priority Framework (main SKILL.md)
  - Debugging → `resources/TROUBLESHOOTING.md`

  That's a four-way triage that keeps the SKILL.md body relevant to the most common case (adding tests) while deferring strategic / troubleshooting work to resources. Well-structured.

  **Test Priority Framework** (line 45-77) — coverage-target matrix (Business logic 80-90%, I/O Key paths, Orchestration 50-60%, UI/CLI Critical paths) is concrete without being dogmatic. *"Test behavior, not implementation"* + *"If refactoring breaks tests but not behavior, tests are too coupled"* — that's the right invariant.

  **Audit Mode** (line 107-175) — mirrors the kind of gap analysis this audit itself is doing. Output format is inline markdown (no saved file) — matches the other inline skills in this subset. The *"Acceptable Gaps"* column is important: orchestration / glue code with no tests is explicitly NOT flagged. That prevents the "100% coverage" rationalization.

  **High-Risk Scenarios** (line 280-354) — DB transactions, Auth/Authz, External API Calls. The DB transactions example (rolled-back transaction fixture + test-both-success-AND-rollback-paths rule) is calibrated against the "partial state" class of bug that's very hard to catch without explicit coverage. The Auth/Authz list (*"403, not 404 — don't leak resource existence"*) is subtle but load-bearing.

  **Anti-patterns table** (line 361-376) — 13 entries, covers the pytest-specific traps (fixture scope pollution, conftest at wrong level, `__init__.py` re-exports) that are easy to get wrong. These are exactly the "hard to debug later" patterns that belong in a skill body.

  **Frontmatter drift:** line 3 has `type: knowledge`. Per frontmatter doc §6 + workflow queue item 7, this moves to `metadata: { type: knowledge }` as part of the repo-wide sweep. Single-line change, coordinated.

  **Cross-audit thread: `code-reviewer` reference at line 394.** Per agents queue items 1-2, model flip opus → sonnet. No skill-text change.

  No output-path drift (no output path — inline findings). No other drift.

  Workshop-shaped: the skill runs in a consumer session, helps the consumer write pytest tests or audit their suite. Assumes nothing beyond "this is a Python + pytest codebase."

- **Action:** at decision point: (1) move `type: knowledge` → `metadata: { type: knowledge }` as part of repo-wide sweep (queue item 7), (2) no independent action.
- **Scope:** trivial — 1-line frontmatter change, covered by sweep.

### `design-tests/resources/EXAMPLES.md`

- **Tag:** `Keep`
- **Finding:** Concrete pytest pattern reference (349 lines) covering `conftest.py` structure, health checks for graceful skipping, dual real/mock client fixtures, factory fixtures (including auto-incrementing IDs + composed factories), test class organization, and anti-pattern code examples (testing implementation, mocking at wrong level, giant fixture vs factory).

  **Dual fixture pattern** (line 133-172) is genuinely useful: `real_client` skipped-if-unavailable + `mock_client` always-available, with matching `@pytest.mark.unit` / `@pytest.mark.integration` on the test functions. This is the pattern the main skill points at (*"See `resources/EXAMPLES.md` for conftest.py structure, health checks, dual real/mock fixtures, and factory patterns"* — line 230).

  **Anti-pattern code examples** (line 276-349) — three entries (testing implementation, mocking at wrong level, giant fixture vs factory) each with Bad / Good snippets. Complements the main skill's anti-pattern table by showing the *code diff* for the top offenders. Correct specialization: tables in main skill, code in resources.

  Correctly subordinated — referenced exactly twice from the main skill.
- **Action:** none.

### `design-tests/resources/QA_STRATEGY.md`

- **Tag:** `Keep`
- **Finding:** Strategic planning reference (150 lines) for greenfield test plans, release readiness, and coverage audits. Covers Artifact Selection (Test Plan / Test Cases / Regression Suite / Bug Report / Acceptance Criteria Review), Expert QA Mindset (when to escalate bugs, handling flaky tests, bug triage heuristics), Edge Cases (missing requirements, limited environments, time pressure), Release Readiness (entry/exit criteria, regression suite tiers).

  **Expert QA Mindset section** is the strongest — *"Think like a saboteur"* + explicit escalation tiers (Immediate / Within hours / Normal triage) + flaky test identification/investigation/remediation matrix. This is the kind of experience-encoded content that's easy to hand-wave in a skill but explicit here.

  **Bug Report Triage Heuristics** — *"Group by area first — 5 bugs in checkout > 5 bugs across 5 modules (systemic vs scattered)"* + *"Check report velocity — 3 reports/week on the same area means it's getting worse"*. These are non-obvious prioritization rules that prevent the "everything is P1" anti-pattern.

  **Defect clustering heuristic** (*"80% of bugs come from 20% of modules"*) — with the specific guidance *"If you're writing a test plan and don't know where bugs cluster, ask for the bug history first."* Calibrated for the LLM's tendency to test uniformly.

  Correctly subordinated — referenced at multiple decision points in the main skill's entry tree. Correct split: strategy in this file, implementation patterns in SKILL.md + EXAMPLES.md, troubleshooting in TROUBLESHOOTING.md.
- **Action:** none.

### `design-tests/resources/TROUBLESHOOTING.md`

- **Tag:** `Keep`
- **Finding:** Debugging reference (70 lines) for common pytest failures: fixture not found, import errors at collection, fixture cleanup failures, flaky tests.

  **Fixture Not Found** section has the key rule up front: *"`conftest.py` fixtures are available to tests in the same directory and all subdirectories, never sideways."* That's the one rule that trips up 80% of fixture-not-found incidents; putting it first is correct.

  **Import Errors at Collection** — four-row cause/fix table covers the common failure modes (missing `__init__.py`, wrong pytest directory, non-editable install, src/ layout without path config). Concrete remediation in each row (*"Add `pythonpath = ["src"]` to `[tool.pytest.ini_options]`"*) — not vague advice.

  **Flaky Tests** decision tree is three-way (CI-only vs everywhere vs `-x`-only) with specific remediation at each leaf. Matches the QA_STRATEGY.md flaky tests investigation list but from the "I'm debugging right now" perspective vs the "I'm planning a stability pass" perspective. Correct to have both.

  Shortest of the three resources, appropriately — troubleshooting reference should be scannable, not comprehensive.
- **Action:** none.

---

## Cross-cutting notes

- **Output-shape diversity is the defining feature of this subset.** Only `refactor` saves an output file; `review-security` and `design-tests` present findings inline. This is deliberate — security findings age poorly (saved audits become stale liability), and test-design guidance is read-and-apply not archive-and-return. Output shape follows the artifact's half-life. The workflow subset's skills were largely file-producing (brainstorm, analyze-idea, write-handoff); code-quality skills are mostly inline. Neither convention is "right" — the shape should match what the artifact is *for*.

  Implication for future skill design: the default should *not* be "always save a file." Saved artifacts should be skills whose output is reviewed later or by someone else; inline skills are for analysis the user acts on immediately in-session.

- **`type:` frontmatter drift — 1 instance in this subset (`design-tests: type: knowledge`).** Plus 4 in the workflow subset. Repo-wide sweep to `metadata: { type: knowledge|command }` is the right coordinated fix (workflow queue item 7). No additional instances found in refactor or review-security.

- **`code-reviewer` agent is the most-referenced agent in this subset** (4 instances across all 3 skills). All references are about verification / quality-review complement to the skill's own analysis. Per agents queue items 1-2, the agent is being flipped to sonnet — no skill-text changes needed, just cross-reference visibility.

- **`/brainstorm-idea` references — 3 in `refactor`, 0 elsewhere.** The refactor skill uses `/brainstorm-idea` for the "escalate architectural issues to design exploration" pattern. Per workflow queue item 3, that skill is being renamed to `/brainstorm-feature`. Three references update in lockstep when the rename ships.

- **No `pattern-finder` references in any code-quality skill** — so the agents queue item 8 (pattern-finder fate: deprecate / sharpen / keep) doesn't create any cascade into this subset. Contrast with workflow subset's `analyze-idea`, which does reference pattern-finder.

- **Scope discipline is consistent.** Each skill is explicit about what it *doesn't* do:
  - `refactor` "When NOT to Use": mechanical renames, code style, performance optimization.
  - `review-security` "Hard exclusions": DoS, theoretical races, missing hardening, test files, env vars.
  - `design-tests` "Acceptable Gaps": orchestration/glue code with no tests.

  That's the right shape for narrow, focused skills — each explicitly de-scopes the adjacent territory rather than quietly expanding to cover everything.

- **No orchestration-shaped leakage** in any of the 3 skills or the 4 resource files. Every skill/resource assumes it runs inside a user session, reads/writes local files (or just presents findings), and returns. Correct workshop identity.

- **`resources/` subdirectory pattern is used by 2 of 3 skills** (`review-security/resources/DOMAINS.md`; `design-tests/resources/EXAMPLES.md` + `QA_STRATEGY.md` + `TROUBLESHOOTING.md`). Correctly subordinated: main SKILL.md has decision framework; resources have concrete patterns, language-specific code samples, or strategic references. Matches the `shape-proposal/resources/` pattern from the workflow subset. No drift.

- **`design-tests` is Python-only by deliberate choice — accepted scope.** Description scope is pytest-specific; all code samples are Python; resource files are Python-specific. Not a drift and not a future concern — this is the declared lane. Non-Python consumers are out of scope for this skill by design. If that ever changes, a parallel skill (not an expansion of this one) would be the right shape, but nothing is queued.

---

## Decision-point queue (carry forward)

Every item below is a real work item. None are blocked behind the v3 reshape — they're just audit-surfaced issues that get scheduled like any backlog work.

**Resolved during review (pending execution — needs diagnostic first):**

1. `review-security/SKILL.md` — **worthyness diagnostic.** User flag: skill has never been invoked in the wild (to user's knowledge). Run invocation-frequency check (same pattern as pattern-finder queue item 8). Based on data, pick: (a) Keep — content is already solid; (b) Sharpen description triggers and/or add surfacing-hook path (coordinates with workflow queue item 6); (c) Deprecate — remove skill, update `docs/indexes/SKILLS.md`, remove from distributions. CC's built-in `/security-review` may already cover enough of the surface.

**Coordinated with other audit directories:**

2. `design-tests/SKILL.md` line 3 — **`type: knowledge` → `metadata: { type: knowledge }`** as part of the repo-wide sweep (workflow queue item 7). One-line change; covered by the coordinated commit, no independent action.

3. `refactor/SKILL.md` lines 47, 105, 210 — **update three `/brainstorm-idea` references → `/brainstorm-feature`** when the brainstorm rename ships (workflow queue item 3). Semantic-preserving; part of the coordinated rename commit.

4. All 3 skills (`refactor`, `review-security`, `design-tests`) — **`code-reviewer` agent references carry forward with no text change** when the agents audit flips the agent's model opus → sonnet (agents queue items 1-2). Purely a cross-ref note — no action here.

**Still open / low-priority:**

5. **Output-shape convention doc** — the deliberate split between file-saving skills (workflow-shaped) and inline-findings skills (review-shaped) isn't currently documented anywhere. A one-paragraph note in `relevant-toolkit-context.md` on "when to save vs present inline" would make the convention learnable. Polish, not v3-blocking.
