---
name: evaluate-batch
description: Use when evaluating multiple resources of one type. Keywords: batch evaluation, parallel evaluation, bulk evaluate, evaluate all, mass evaluation.
argument-hint: "[type] [re-evaluate]"
allowed-tools: Read, Write, Glob, Agent, Bash(jq:*)
---

Use when evaluating multiple resources of a single type in parallel.

## Why Batch?

Batch evaluation extracts the pattern. Instead of you crafting the evaluation prompt each time, this skill:
- Standardizes the agent prompt format
- Handles JSON collection and merging
- Manages evaluations.json updates

The value is **consistency and reduced cognitive load**, not just parallelism.

### When NOT to Batch

| Situation | Why Individual is Better |
|-----------|-------------------------|
| Iterating on one resource | Batch overhead not worth it for 1 item |
| Deep-dive review | Individual evaluation allows follow-up questions |
| Debugging evaluation issues | Easier to trace single agent |

### Token Economics

Each parallel agent consumes ~10-15K tokens (skill load + resource + evaluation). Batch of 5 = ~50-75K tokens in one burst.

**Cost control:** For 20+ resources, run sequential batches of 5 rather than one massive parallel run. This:
- Avoids API rate limits
- Lets you stop early if patterns emerge
- Reduces wasted tokens if early evaluations reveal systematic issues

### Early Stopping Criteria

After each batch, check results before continuing:

| Pattern | Action |
|---------|--------|
| 3+ resources with same D1 issue | Pause - fix systematic problem first |
| All percentages below 60% | Stop - fundamental quality issue needs addressing |
| Same `top_improvement` repeated | Fix that issue across resources before continuing |

## Parameters

Parse from `$ARGUMENTS` (e.g., `/evaluate-batch skills re-evaluate`):

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

- **Always exclude** `personal-` memories — personal memories are not evaluated
- If specific resources are listed in the invocation, evaluate exactly those — skip staleness checks
- Otherwise, read `docs/indexes/evaluations.json` and include resources that are:
  - **Unevaluated**: Not in `{type}.resources`
  - **Stale**: `file_hash` doesn't match current file (`md5sum <file> | cut -c1-8`), OR the evaluate-* skill itself has changed since last evaluation

Use the staleness check:
```bash
.claude/scripts/evaluation-query.sh unevaluated  # missing evaluations
.claude/scripts/evaluation-query.sh stale        # hash mismatch
```

**Note:** Hash-based staleness only catches resource changes. If the evaluate-* skill rubric has changed, resources may need re-evaluation even with matching hashes. When the user requests a full re-evaluation, skip staleness checks entirely.

### 3. Process Batches (Write After Each)

For each batch of resources (up to batch-size):

**3a. Launch parallel agents:**

Agent prompt template:
```
Launch agent with prompt:
"Run /evaluate-{singular-type} on {resource-name} ({resource-path}).

Return results in JSON format:
{
  "name": "...",
  "file_hash": "...",
  "score": ...,
  "max": ...,
  "percentage": ...,
  "dimensions": { "D1": ..., ... },
  "top_improvements": ["...", "...", "..."]
}
"
```

Concrete example (evaluating a skill):
```
Run /evaluate-skill on create-hook (/home/user/project/.claude/skills/create-hook/SKILL.md).

Return results in JSON format:
{
  "name": "create-hook",
  "file_hash": "985a90a3",
  "score": ...,
  "max": 120,
  "percentage": ...,
  "dimensions": { "D1": ..., "D2": ..., "D3": ..., "D4": ..., "D5": ..., "D6": ..., "D7": ..., "D8": ... },
  "top_improvements": ["...", "...", "..."]
}
```

Type mapping:
- `skills` → `/evaluate-skill`
- `hooks` → `/evaluate-hook`
- `memories` → `/evaluate-memory`
- `agents` → `/evaluate-agent`

**3b. Collect batch results:**
Wait for batch agents to complete. Parse JSON from each response.

**3c. Write batch to evaluations.json immediately:**
Add each result to `docs/indexes/evaluations.json` under `{type}.resources.{name}`:

```json
{
  "file_hash": "...",
  "date": "YYYY-MM-DD",
  "score": ...,
  "max": ...,
  "percentage": ...,
  "dimensions": { ... },
  "top_improvements": [ ... ]
}
```

**3d. Report batch summary:**
```
Batch 1/3 complete:
| Resource | Score | % |
|----------|-------|---|
| name-1   | 108/120 | 90.0% |
| name-2   | 105/120 | 87.5% |
```

**Why write after each batch:** If later batches fail or timeout, earlier results are already saved. Re-running the command will skip already-evaluated resources.

### 4. Final Summary

After all batches complete:

```
| Resource | Score | % |
|----------|-------|---|
| name-1   | 108/120 | 90.0% |
| name-2   | 105/120 | 87.5% |
...

Added N evaluations to docs/indexes/evaluations.json
```

## When to Use Each Parameter

| Scenario | Settings |
|----------|----------|
| Fill gaps + refresh stale | Default (unevaluated + stale) |
| Full quality audit | `re-evaluate=true` |
| Rubric changed | `re-evaluate=true` — resource hashes match but scores are stale because the rubric itself changed |
| Large resource set (10+) | `batch-size=3` to avoid timeouts |
| Quick spot-check | `batch-size=2` on specific type |
| Specific resources listed | Evaluates exactly those, skips all staleness checks |

## Calibration Notes

| Default | Why |
|---------|-----|
| `batch-size=5` | Balances parallelism vs. agent timeout risk (~2min each) |
| Unevaluated + stale | Covers gaps and refreshes modified resources automatically |

| Resource Count | Recommended Strategy |
|----------------|---------------------|
| 1-5 | Single batch, default settings |
| 6-15 | Two batches, `batch-size=5` |
| 15+ | Three+ batches with `batch-size=3` to avoid context pressure |

### Dependency Order

Evaluate in this order when doing full audit:
1. **Skills** first - agents may reference skill patterns
2. **Hooks** second - independent, no cross-refs
3. **Memories** third - may reference skills
4. **Agents** last - often reference skills and patterns

**Detection:** Check agent files for `/skill-name` references to identify dependencies.

**Score normalization:** Each resource type has its own dimension structure and max score (e.g., skills: /120, agents: /115, hooks: /115). The `percentage` field normalizes across types — use it for cross-type comparisons and thresholds (e.g., 85% quality gate).

## Error Handling

| Error | Recovery |
|-------|----------|
| Agent fails/times out | Note failure, continue with others, report at end |
| JSON parse error | Extract what's available, flag for manual review |
| evaluations.json missing | Create with empty `{type}.resources` |
| No resources to evaluate | Report "0 resources found" and exit |

### Resuming Interrupted Batches

Since results are written after each batch completes:
1. Completed batches are already in evaluations.json
2. Run same command again - Filter step skips already-evaluated resources
3. Only remaining batches will be processed

**Example - 15 resources, batch-size=5, interrupted after batch 2:**
```
Batch 1: 5 evaluated → written to evaluations.json
Batch 2: 5 evaluated → written to evaluations.json
Batch 3: interrupted before completion
Re-run → Filter finds only 5 remaining → single batch needed
```

## Example Invocation

```
/evaluate-batch agents
/evaluate-batch skills batch-size=3
/evaluate-batch hooks re-evaluate=true
```

### Complete Worked Example

**Command:** `/evaluate-batch hooks`

**Step 1 - Find:** 8 hooks in `.claude/hooks/*.sh`

**Step 2 - Filter:** Check evaluations.json
- 6 already evaluated with matching file_hash
- 2 stale (secrets-guard, session-start modified)
- Result: 2 to evaluate

**Step 3 - Launch:** 2 parallel agents (within batch-size=5)

**Step 4 - Collect:** Both return JSON

**Step 5 - Update:** Merge into evaluations.json

**Step 6 - Report:**
```
| Resource      | Score | % |
|---------------|-------|---|
| secrets-guard | 95/115  | 82.6% |
| session-start | 103/115 | 89.6% |

Added 2 evaluations to docs/indexes/evaluations.json
```

## Anti-Patterns

| Pattern | Problem | Fix |
|---------|---------|-----|
| **Bypassing skills** | Each evaluator outputs different JSON structures and dimension names — manually writing evaluation logic produces inconsistent formats that break evaluations.json merging and cross-resource comparisons | Always use `/evaluate-{type}` skills via agents |
| **Serial execution** | Running one at a time | Use parallel Task calls up to batch-size |
| **Over-parallelizing** | Burns tokens fast, hits API throughput limits | Keep batch-size ≤5, run batches sequentially |
| **Missing JSON format** | Agent returns prose, not structured data | Explicitly request JSON in agent prompt |
| **Write at end only** | Lose all progress if later batch fails | Write to evaluations.json after each batch |
