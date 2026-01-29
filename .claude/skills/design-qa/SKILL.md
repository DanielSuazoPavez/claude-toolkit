---
name: design-qa
description: Design test plans, QA strategies, regression suites, and bug triage workflows. Use when requests mention "test plan", "QA strategy", "regression testing", "test coverage", "bug report", "quality assurance", "manual testing", "acceptance criteria", or "release testing".
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

## Expert QA Mindset

**Think like a saboteur**: Your job is to break the system before users do.

### Risk-Based Testing
Focus effort where failures hurt most:
1. **Money paths** - Payment, billing, refunds
2. **Data integrity** - User data, transactions
3. **Security boundaries** - Auth, permissions
4. **High-traffic flows** - Login, search, checkout

### Test Prioritization

| Impact | Likelihood | Priority |
|--------|------------|----------|
| High | High | P0 - Test first |
| High | Low | P1 - Test thoroughly |
| Low | High | P2 - Test basic paths |
| Low | Low | P3 - Test if time permits |

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

### Writing Effective Bug Reports

**Title formula**: `[Area] Specific symptom + trigger condition`
- Bad: "Login broken"
- Good: "[Login] OTP verification fails when phone number has leading zeros"

**Minimum viable bug report**:
1. **Steps to reproduce** (numbered, specific actions)
2. **Expected result** (what should happen)
3. **Actual result** (what happens instead)
4. **Environment** (browser, OS, user role, data state)

**Bonus for faster fixes**: screenshot/video, console errors, network trace, account credentials used.

### Acceptance Criteria Validation

When reviewing acceptance criteria before testing:
- **Testable?** Can you write a pass/fail test for it?
- **Complete?** What about error states, edge cases, permissions?
- **Measurable?** "Fast" is vague; "< 2 seconds" is testable

Push back on: "works correctly", "handles errors gracefully", "user-friendly"

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
| Vague Steps | "Test the feature" | One action + expected result per step |
| Missing Preconditions | Test fails on setup | Document setup, test data, user state |
| Happy Path Only | Misses real failures | Boundaries, empty states, errors |
| Generic Bug Title | "Login broken" | "[Login] OTP fails with leading zeros" |

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
