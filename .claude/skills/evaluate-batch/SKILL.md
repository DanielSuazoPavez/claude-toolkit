---
name: evaluate-batch
description: Batch evaluate resources by type. Use when evaluating multiple skills, hooks, memories, or agents at once.
---

Use when evaluating multiple resources of a single type in parallel.

## Parameters

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `type` | Yes | - | Resource type: `skills`, `hooks`, `memories`, `agents` |
| `batch-size` | No | 5 | Max parallel evaluations |
| `re-evaluate` | No | false | Include already-evaluated resources |

## Process

### 1. Find Resources

```
skills:   .claude/skills/*/SKILL.md
hooks:    .claude/hooks/*.sh
memories: .claude/memories/*.md
agents:   .claude/agents/*.md
```

### 2. Filter

- Read `.claude/evaluations.json`
- Unless `re-evaluate=true`, exclude resources already in `{type}.resources`

### 3. Launch Parallel Agents

For each resource (up to batch-size at a time):

```
Launch agent with prompt:
"Run /evaluate-{singular-type} on {resource-name} ({resource-path}).

Return results in JSON format:
{
  "name": "...",
  "grade": "...",
  "score": ...,
  "max": ...,
  "percentage": ...,
  "dimensions": { "D1": ..., ... },
  "top_improvements": ["...", "...", "..."]
}
"
```

Type mapping:
- `skills` → `/evaluate-skill`
- `hooks` → `/evaluate-hook`
- `memories` → `/evaluate-memory`
- `agents` → `/evaluate-agent`

### 4. Collect Results

Wait for all agents to complete. Parse JSON from each response.

### 5. Update evaluations.json

Add each result to `.claude/evaluations.json` under `{type}.resources.{name}`:

```json
{
  "date": "YYYY-MM-DD",
  "grade": "...",
  "score": ...,
  "max": ...,
  "percentage": ...,
  "dimensions": { ... },
  "top_improvements": [ ... ]
}
```

### 6. Report Summary

Output a summary table:

```
| Resource | Grade | Score |
|----------|-------|-------|
| name-1   | A     | 93/100 |
| name-2   | A-    | 89/100 |
...

Added N evaluations to .claude/evaluations.json
```

## When to Use Each Parameter

| Scenario | Settings |
|----------|----------|
| Fill empty evaluations.json | Default (new resources only) |
| Quality audit after changes | `re-evaluate=true` |
| Large resource set (10+) | `batch-size=3` to avoid timeouts |
| Quick spot-check | `batch-size=2` on specific type |

## Calibration Notes

| Default | Why |
|---------|-----|
| `batch-size=5` | Balances parallelism vs. agent timeout risk (~2min each) |
| New resources first | Re-evaluating stable resources rarely changes scores |

| Resource Count | Recommended Strategy |
|----------------|---------------------|
| 1-5 | Single batch, default settings |
| 6-15 | Two batches, `batch-size=5` |
| 15+ | Three+ batches with `batch-size=3` to avoid context pressure |

**Ordering:** Evaluate in dependency order when possible (skills before agents that reference them) - evaluations are independent but shared context helps.

**Score normalization:** All evaluations output scores as percentage (0-100) regardless of the underlying dimension structure.

## Error Handling

| Error | Recovery |
|-------|----------|
| Agent fails/times out | Note failure, continue with others, report at end |
| JSON parse error | Extract what's available, flag for manual review |
| evaluations.json missing | Create with empty `{type}.resources` |
| No resources to evaluate | Report "0 resources found" and exit |

## Example Invocation

```
/evaluate-batch agents
/evaluate-batch skills batch-size=3
/evaluate-batch hooks re-evaluate=true
```

## Anti-Patterns

| Pattern | Problem | Fix |
|---------|---------|-----|
| **Bypassing skills** | Manually writing evaluation logic | Always use `/evaluate-{type}` skills via agents |
| **Serial execution** | Running one at a time | Use parallel Task calls up to batch-size |
| **Missing JSON format** | Agent returns prose, not structured data | Explicitly request JSON in agent prompt |
