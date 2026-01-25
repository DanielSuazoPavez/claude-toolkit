---
name: qa-test-planner
description: Generate test plans, manual test cases, regression suites, and bug reports. Use when planning testing strategy, writing test cases, building regression suites, or documenting bugs.
disable-model-invocation: true
---

# QA Test Planner

Create comprehensive testing documentation.

## Expert QA Mindset

**Think like a saboteur**: Your job is to break the system before users do.

### Risk-Based Testing
Focus effort where failures hurt most:
1. **Money paths** - Payment, billing, refunds
2. **Data integrity** - User data, transactions
3. **Security boundaries** - Auth, permissions
4. **High-traffic flows** - Login, search, checkout

### When to Stop Testing
- Time-boxed: Allocate fixed time per risk level
- Diminishing returns: New tests find fewer bugs
- Coverage plateau: Critical paths covered
- Risk accepted: Stakeholder sign-off on gaps

### Test Prioritization Matrix

| Impact | Likelihood | Priority |
|--------|------------|----------|
| High | High | P0 - Test first |
| High | Low | P1 - Test thoroughly |
| Low | High | P2 - Test basic paths |
| Low | Low | P3 - Test if time permits |

## Deliverables

| Task | Output | Time |
|------|--------|------|
| Test Plan | Strategy, scope, schedule, risks | 10-15 min |
| Test Cases | Step-by-step with expected results | 5-10 min each |
| Regression Suite | Smoke tests, critical paths | 15-20 min |
| Bug Report | Reproducible steps, evidence | 5 min |

## Test Case Template

```markdown
## TC-001: [Title]

**Priority:** P0/P1/P2/P3
**Type:** Functional | UI | Integration

### Preconditions
- [Setup requirement]
- [Test data needed]

### Steps
1. [Action]
   **Expected:** [Result]

2. [Action]
   **Expected:** [Result]

### Test Data
- Input: [values]
- User: [test account]
```

## Bug Report Template

```markdown
# BUG-[ID]: [Clear title]

**Severity:** Critical | High | Medium | Low
**Priority:** P0 | P1 | P2 | P3

## Environment
- OS: [Windows 11, macOS, etc.]
- Browser: [Chrome 120, etc.]
- Build: [version]

## Steps to Reproduce
1. [Specific step]
2. [Specific step]

## Expected
[What should happen]

## Actual
[What happens]

## Evidence
- Screenshot: [attached]
- Console errors: [if any]
```

## Severity Definitions

| Level | Criteria | Example |
|-------|----------|---------|
| Critical (P0) | System crash, data loss, security | Payment fails |
| High (P1) | Major feature broken, no workaround | Search broken |
| Medium (P2) | Feature partial, workaround exists | Filter missing option |
| Low (P3) | Cosmetic, rare edge cases | Typo, alignment |

## Regression Suite Types

| Suite | Duration | When | Coverage |
|-------|----------|------|----------|
| Smoke | 15-30 min | Daily | Critical paths |
| Targeted | 30-60 min | Per change | Affected areas |
| Full | 2-4 hours | Weekly/Release | Comprehensive |
| Sanity | 10-15 min | After hotfix | Quick validation |

## Pass/Fail Criteria

**PASS:**
- All P0 tests pass
- 90%+ P1 tests pass
- No critical bugs open

**FAIL (Block Release):**
- Any P0 test fails
- Critical bug discovered
- Security vulnerability

## Anti-Patterns

| Pattern | Problem | Fix |
|---------|---------|-----|
| **Vague Steps** | "Test the feature" - not reproducible | Specific actions + expected results per step |
| **Missing Preconditions** | Test fails due to setup not documented | Document all setup, test data, user state |
| **Generic Bug Title** | "Login doesn't work" - unclear scope | Specific: "[Login] OTP fails when code contains leading zeros" |
| **Happy Path Only** | Misses edge cases users will hit | Include boundary values, empty states, errors |
| **No Priority** | Everything looks equally important | Assign P0-P3 based on impact × likelihood |

## Writing Reproducible Steps

**Bad:** "Test login functionality"

**Good:**
```markdown
1. Navigate to https://app.example.com/login
   **Expected:** Login form displays with email/password fields

2. Enter "test@example.com" in email field
   **Expected:** Input accepted, no validation errors

3. Enter "wrongpassword" in password field
   **Expected:** Input masked with dots

4. Click "Sign In" button
   **Expected:** Error message "Invalid credentials" appears within 2 seconds
```

**The rule:** Each step = one action + one expected result. No compound steps.

## Risk → Test Effort Matrix

```
High Impact + High Likelihood → P0: Test first, test deeply
├─ Payment flows, auth, data mutations
│
High Impact + Low Likelihood → P1: Test thoroughly
├─ Edge cases in critical paths, error recovery
│
Low Impact + High Likelihood → P2: Test basic paths
├─ UI quirks, minor features
│
Low Impact + Low Likelihood → P3: Test if time permits
└─ Cosmetic issues, rare configurations
```

## Test Plan Outline

1. **Scope**: In/out of scope
2. **Strategy**: Test types, approach
3. **Environment**: OS, browsers, devices
4. **Entry Criteria**: When to start testing
5. **Exit Criteria**: When testing is done
6. **Risks**: What could go wrong

## Checklist

**Test Plan:**
- [ ] Scope clearly defined
- [ ] Entry/exit criteria specified
- [ ] Risks identified

**Test Cases:**
- [ ] Each step has expected result
- [ ] Preconditions documented
- [ ] Priority assigned

**Bug Reports:**
- [ ] Reproducible steps
- [ ] Environment documented
- [ ] Evidence attached
