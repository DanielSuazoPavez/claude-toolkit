---
name: design-qa
type: knowledge
description: Design test plans, QA strategies, regression suites, and bug triage workflows. Use when requests mention "test plan", "QA strategy", "regression testing", "test coverage", "bug report", "acceptance criteria", or "release testing".
disable-model-invocation: true
---

# QA Test Planner

Create testing documentation with expert-level quality judgment.

## Quick Start

Describe what you need:
```
create a test plan for the new checkout flow
write test cases for user authentication
design a regression suite for the payments module
```

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

### Test Debt Signals

Push back on shipping without tests when you see these:
- **Changelog churn**: Same module appears in 3+ recent bug fixes — it's accumulating debt faster than you're paying it down
- **Tribal knowledge gates**: Only one person knows how to test a feature manually — that's unwritten test coverage with a bus factor of 1
- **"It worked on my machine" frequency**: >2 occurrences/sprint means environment-dependent behavior isn't covered
- **Regression recidivism**: A bug you fixed last month is back — the fix wasn't verified with a regression test

**Debt accumulation rate**: Each shipped feature without tests adds ~1.5x its original test effort as future debt (context loss, behavior drift, integration surface growth). Three consecutive untest sprints typically means a dedicated test-writing sprint is cheaper than continued ad-hoc fixing.

## Expert Heuristics

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

### Estimating Test Coverage Time

**Quick estimation formula**: `(features × 2) + (integrations × 3) + (risk_factors × 4)` hours

| Component | Smoke (min) | Full (hours) |
|-----------|-------------|--------------|
| Simple CRUD feature | 15 | 2-4 |
| Payment integration | 30 | 4-8 |
| Auth/permissions | 30 | 4-6 |
| File upload/export | 20 | 2-3 |
| Third-party API | 45 | 6-8 |

**Multipliers**: Mobile +50%, accessibility +30%, i18n +20% per locale

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

## Anti-Patterns

| Pattern | Problem | Fix |
|---------|---------|-----|
| **Testing implementation, not behavior** | Tests break on refactor even when feature works fine | Write tests against observable outcomes, not internal steps |
| **Over-mocking hides integration bugs** | Unit tests pass, production breaks at boundaries | Reserve mocks for external services; test real integrations where feasible |
| **Copy-paste test plans** | Reused plans miss feature-specific risks | Start from risk analysis, not templates |
| **Conflating severity with priority** | P1 cosmetic bugs block release while P3 data loss waits | Severity = impact, priority = business urgency. A low-severity bug on the checkout page can be high priority |
| **Testing everything equally** | 200 test cases, all medium priority, no one runs them all | Risk-weight: P0 paths get exhaustive coverage, P3 gets smoke only |
| **Happy path only** | Misses real failures | Boundaries, empty states, error paths, concurrent access |

## Rationalizations

| Rationalization | Counter |
|-----------------|---------|
| "These edge cases are unlikely" | Unlikely × high-impact = P1. Check the risk matrix. |
| "The code looks correct, no need to test" | Code review finds logic errors. Testing finds integration errors. Different coverage. |
| "We'll catch it in production" | Production bugs cost 10x. Test environment exists for a reason. |
| "Just a minor UI change, skip regression" | Minor changes break unexpected paths. Smoke test at minimum. |
| "We don't have time to test everything" | That's what prioritization is for. P0 paths get 100%, P3 gets skipped with documented risk. |

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

## See Also

- `/design-tests` — Sister skill for pytest implementation. Use design-qa for test strategy and planning, design-tests for writing the actual test code.
- `code-reviewer` agent — Complements QA with code-level review; may identify test coverage gaps.
- `code-debugger` agent — For systematic bug investigation after QA identifies failures.
