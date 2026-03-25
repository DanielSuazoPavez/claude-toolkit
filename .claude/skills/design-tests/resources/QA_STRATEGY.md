# QA Strategy & Planning Reference

Strategic test planning for greenfield projects, release readiness, and coverage audits. Return to the main skill for pytest implementation patterns.

## Table of Contents

1. [Artifact Selection](#artifact-selection)
2. [Expert QA Mindset](#expert-qa-mindset)
3. [Edge Cases](#edge-cases)
4. [Release Readiness](#release-readiness)
5. [Quick Reference](#quick-reference)

---

## Artifact Selection

| User needs... | Produce | Key sections |
|---------------|---------|--------------|
| Strategy before a release | **Test Plan** | Scope, risk matrix, schedule, entry/exit criteria |
| Specific scenarios to execute | **Test Cases** | Preconditions, steps, expected/actual, priority |
| Repeatable post-deploy checks | **Regression Suite** | Tiered (smoke/targeted/full), automation candidates |
| Bug documentation | **Bug Report** | Repro steps, environment, severity, triage recommendation |
| Validate story completeness | **Acceptance Criteria Review** | Testability audit, gap list, suggested additions |

When unclear, start with the test plan — it surfaces scope and risk before committing to specifics.

## Expert QA Mindset

**Think like a saboteur**: Your job is to break the system before users do.

### When to Escalate Bugs

**Escalate immediately** (don't wait for triage):
- Data corruption or loss affecting production
- Security vulnerabilities (auth bypass, data exposure)
- Payment/billing failures
- Compliance violations (GDPR, HIPAA)

**Escalate within hours**:
- Core feature completely broken, no workaround
- Bug affecting >10% of users
- Performance degradation >50%

**Normal triage process**:
- Feature partially broken with workaround
- Edge cases, cosmetic issues
- Low-traffic features

### Handling Flaky Tests

**Identification**:
- Same test fails/passes on identical code
- Failures correlate with time-of-day, load, or parallel runs
- Error messages mention timeouts, race conditions, or "element not found"

**Investigation checklist**:
1. Is it timing-dependent? (async waits, animations, network)
2. Is it order-dependent? (shared state, database pollution)
3. Is it environment-dependent? (resources, external services)

**Remediation by cause**:
| Cause | Fix |
|-------|-----|
| Timing | Explicit waits for conditions, not fixed sleeps |
| Shared state | Isolate test data, reset between tests |
| External service | Mock/stub, or mark as integration test |
| Resource contention | Reduce parallelism, increase timeouts |

**When to quarantine**: If fix takes >2 hours and it's blocking CI, quarantine with ticket. Review quarantine weekly.

### Bug Report Triage Heuristics

**Title formula**: `[Area] Specific symptom + trigger condition`
- Bad: "Login broken"
- Good: "[Login] OTP verification fails when phone number has leading zeros"

**Prioritizing a bug backlog** — when everything is "high priority":
1. **Group by area first** — 5 bugs in checkout > 5 bugs across 5 modules (systemic vs scattered)
2. **Check report velocity** — 3 reports/week on the same area means it's getting worse, not stable
3. **Close-as-wontfix when**: workaround exists AND <5 users affected AND fix requires architectural change. Document the workaround in the ticket.
4. **Duplicate bugs signal systemic issues** — 4 "login is slow" reports aren't 4 bugs, they're 1 performance investigation

**When a bug report is actually a feature request**: If expected behavior was never specified and the current behavior is internally consistent, it's a requirements gap. Route to product, not engineering.

### Acceptance Criteria Validation

Push back on untestable criteria: "works correctly", "handles errors gracefully", "user-friendly". Each criterion needs a pass/fail condition.

**Defect clustering heuristic**: 80% of bugs come from 20% of modules. Track where bugs cluster — those modules need disproportionately more test coverage, not equal treatment. If you're writing a test plan and don't know where bugs cluster, ask for the bug history first.

## Edge Cases

### Testing with Missing Requirements

When specs are incomplete:
1. **Document assumptions** - Write what you assume the behavior should be
2. **Test the obvious** - Happy path, empty/null inputs, boundaries
3. **Flag unknowns** - Mark test cases as "needs clarification" with specific questions
4. **Test what exists** - Use the UI/API as the source of truth for current behavior

Ask stakeholders: "If X happens, should the system do Y or Z?"

### Testing with Limited Environments

When you can't reproduce production:
- **Prioritize risks** - Focus on logic, not environment-specific behavior
- **Document gaps** - "Not tested: IE11, mobile Safari, screen readers"
- **Use feature flags** - Test in production behind flags if staging differs
- **Request access** - Escalate if critical paths can't be tested

### Testing Under Time Pressure

When you have hours, not days:
1. **Smoke test critical paths only** (login, core feature, checkout)
2. **Focus on changed code** - What was actually modified?
3. **Test boundaries first** - 0, 1, max, empty, special characters
4. **Document what's NOT tested** - Risk acceptance by stakeholder

**Minimum viable testing**:
- P0 paths: 100% coverage
- P1 paths: Happy path only
- P2/P3: Skip with documented risk

## Release Readiness

### Entry Criteria (start testing)
- Code complete, deployed to test environment
- Test data available, environment stable
- Requirements/specs accessible

### Exit Criteria (ship it)
- **PASS**: All P0 pass, 90%+ P1 pass, no critical bugs open
- **FAIL (block release)**: Any P0 fails, critical bug, security vulnerability

### Regression Suite Tiers

| Tier | Scope | When to Run | Duration |
|------|-------|-------------|----------|
| Smoke | Critical paths only | Every deploy | 15-30 min |
| Targeted | Changed features + dependencies | PR merge | 1-2 hours |
| Full | Everything | Release candidate | 4-8 hours |

## Quick Reference

| Task | Key Elements |
|------|--------------|
| Test Plan | Scope, risks, schedule, entry/exit criteria |
| Test Case | Preconditions, steps, expected result, priority |
| Bug Report | Steps to reproduce, expected vs actual, environment |
| Regression Suite | Tiered (smoke/targeted/full), pass/fail criteria |
