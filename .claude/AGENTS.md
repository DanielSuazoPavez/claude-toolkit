# Agents Index

Specialized agents for complex, multi-step tasks.

## Codebase Analysis

| Agent | Status | Description | Tools |
|-------|--------|-------------|-------|
| `codebase-explorer` | alpha | Explores codebase and writes structured analysis to `.claude/reviews/codebase/`. Use for onboarding or understanding architecture. | Read, Bash, Grep, Glob, Write |
| `pattern-finder` | new | Documents how things are implemented - finds examples of patterns | Read, Bash, Grep, Glob |

## Code Quality

| Agent | Status | Description | Tools |
|-------|--------|-------------|-------|
| `code-reviewer` | stable | Pragmatic code reviewer focused on real risks, proportional to project scale | Read, Grep, Glob, Bash |
| `code-debugger` | new | Investigates bugs using scientific method with persistent state | Read, Write, Edit, Bash, Grep, Glob |

## Verification

| Agent | Status | Description | Tools |
|-------|--------|-------------|-------|
| `goal-verifier` | beta | Verifies work is actually complete (L1: exists, L2: substantive, L3: wired). Writes report to `.claude/reviews/`. | Read, Bash, Grep, Glob, Write |
| `implementation-checker` | stable | Compares implementation to planning docs, writes report to `.claude/reviews/` | Read, Grep, Glob, Write |

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
