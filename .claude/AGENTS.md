# Agents Index

Specialized agents for complex, multi-step tasks.

## Codebase Analysis

| Agent | Description | Tools |
|-------|-------------|-------|
| `codebase-mapper` | Explores codebase and writes structured analysis documents to `.planning/codebase/` | Read, Bash, Grep, Glob, Write |
| `pattern-finder` | Documents how things are implemented - finds examples of patterns | Read, Bash, Grep, Glob |

## Code Quality

| Agent | Description | Tools |
|-------|-------------|-------|
| `code-reviewer` | Pragmatic code reviewer focused on real risks, proportional to project scale | Read, Grep, Glob, Bash |
| `code-debugger` | Investigates bugs using scientific method with persistent state | Read, Write, Edit, Bash, Grep, Glob |

## Verification

| Agent | Description | Tools |
|-------|-------------|-------|
| `goal-verifier` | Verifies work is actually complete (L1: exists, L2: substantive, L3: wired) | Read, Bash, Grep, Glob |
| `plan-reviewer` | Compares implementation to planning docs, catches drift | Read, Grep, Glob |

## Usage

Agents are invoked by Claude when appropriate for the task. You can also request them explicitly:

```
Use the codebase-mapper agent to analyze the tech stack
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
4. Use `/agent-judge` to evaluate quality
