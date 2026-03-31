# Agents Index

Specialized agents for complex, multi-step tasks.

## Codebase Analysis

| Agent | Status | Description | Tools |
|-------|--------|-------------|-------|
| `codebase-explorer` | stable | Explores codebase and writes structured analysis to `output/claude-toolkit/reviews/codebase/`. Use for onboarding or understanding architecture. Related: pattern-finder catalogs specific implementation patterns, code-reviewer assesses code quality, /write-docs turns output into documentation. | Read, Bash, Grep, Glob, Write |
| `pattern-finder` | beta | Documents how things are implemented - finds examples of patterns. Related: codebase-explorer maps high-level architecture, code-reviewer assesses quality, code-debugger uses pattern catalog for expected behavior. | Read, Bash, Grep, Glob |

## Code Quality

| Agent | Status | Description | Tools |
|-------|--------|-------------|-------|
| `code-reviewer` | stable | Pragmatic code reviewer focused on real risks, proportional to project scale. Related: code-debugger digs into root causes, goal-verifier checks completeness, /refactor for structural issues, /review-security for deeper vulnerability analysis. | Read, Grep, Glob, Bash, Write |
| `code-debugger` | alpha | Investigates bugs using scientific method with persistent state. Related: code-reviewer surfaces potential problems, pattern-finder shows how things are supposed to work, goal-verifier confirms fixes end-to-end. | Read, Write, Edit, Bash, Grep, Glob |

## Document Review

| Agent | Status | Description | Tools |
|-------|--------|-------------|-------|
| `proposal-reviewer` | beta | Reviews proposals for audience fit, tone consistency, and blind spots. Related: /shape-proposal creates documents to review, /brainstorm-idea for earlier-stage designs, code-reviewer for code quality (vs document quality). | Read, Grep, Glob, Write |

## Verification

| Agent | Status | Description | Tools |
|-------|--------|-------------|-------|
| `goal-verifier` | experimental | Verifies work is actually complete (L1: exists, L2: substantive, L3: wired). Writes report to `output/claude-toolkit/reviews/`. Complementary: implementation-checker checks plan alignment, code-reviewer checks code quality/risks, /wrap-up may invoke verification before merge. **Experimental:** devil's advocate + negative cases added to reduce false-green rate. Restore to `245dba0` if experiment fails. | Read, Bash, Grep, Glob, Write |
| `implementation-checker` | stable | Compares implementation to planning docs, writes report to `output/claude-toolkit/reviews/`. Complementary: goal-verifier checks goal achievement, code-reviewer checks code quality independent of plan, /review-plan reviews plan quality before implementation. | Read, Bash, Grep, Glob, Write |

## Usage

Agents are invoked by Claude when appropriate for the task. You can also request them explicitly:

```
Use the codebase-explorer agent to analyze the tech stack
Use the code-debugger agent to investigate this issue
```

## Creating New Agents

1. Create `.claude/agents/your-agent.md`
2. Include frontmatter:
   ```yaml
   ---
   name: agent-name
   description: One-line description
   tools: Read, Grep, Glob, Bash
   color: cyan  # optional
   ---
   ```
3. Define the agent's role, principles, and output format
4. Use `/evaluate-agent` to evaluate quality
