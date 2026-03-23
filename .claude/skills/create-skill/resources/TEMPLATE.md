---
name: check-dependencies
description: Use when checking project dependencies for outdated versions, security advisories, or unused packages. Keywords: dependencies, outdated, vulnerabilities, audit, packages.
# argument-hint: "[lockfile-path]"  ← uncomment if skill accepts arguments
# user-invocable: false  ← uncomment for knowledge skills (not user-invoked, Claude auto-loads)
---

Use when checking project dependencies for issues.

## When to Use

- Before a release — verify no known vulnerabilities ship
- After adding or upgrading packages — check for conflicts
- Periodic audit — find unused or outdated dependencies

## Process

### 1. Scan the lockfile

Read the lockfile (`package-lock.json`, `poetry.lock`, `Cargo.lock`, etc.) and identify all direct dependencies with their pinned versions.

### 2. Check for advisories

Search for known security advisories against each dependency and version. Flag any with active CVEs or deprecation notices.

### 3. Identify unused dependencies

Grep the codebase for import/require statements. Cross-reference against declared dependencies. Flag any that are declared but never imported.

### 4. Report findings

Write a summary grouped by severity: critical (vulnerabilities), warning (outdated majors), info (minor updates available, unused).

## Anti-Patterns

| Pattern | Problem | Fix |
|---------|---------|-----|
| **Update Everything** | Upgrading all deps at once risks breakage | Prioritize security fixes, batch the rest |
| **Ignore Transitive** | Vulnerability in transitive dep is still a vulnerability | Check full dependency tree, not just direct |
| **No Lockfile** | Reproducibility gone, versions drift | Always commit the lockfile |
