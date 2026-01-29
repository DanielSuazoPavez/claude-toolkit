# Evaluation Tracking System Design

## Problem

Track which resources (skills, agents, hooks, memories) have been evaluated, when, and which need re-evaluation due to modifications.

## Use Cases

- On-demand: "what needs evaluation?"
- Release checklist: ensure everything reviewed before version bump

## Solution

### Storage: `.claude/evaluations.json`

```json
{
  "skills": {
    "evaluate_skill": "/evaluate-skill",
    "write_skill": "/write-skill",
    "dimensions": {
      "D1": { "name": "Clear activation trigger", "max": 10 },
      "D2": { "name": "Appropriate scope", "max": 10 },
      "D3": { "name": "Actionable instructions", "max": 10 },
      "D4": { "name": "Anti-patterns documented", "max": 10 }
    },
    "resources": {
      "write-memory": {
        "scores": { "D1": 8, "D2": 9, "D3": 7, "D4": 8 },
        "total": 32,
        "max": 40,
        "grade": "B+",
        "date": "2026-01-28",
        "version": "1.0.0",
        "file_hash": "a1b2c3d4"
      }
    }
  },
  "hooks": {
    "evaluate_skill": "/evaluate-hook",
    "write_skill": "/write-hook",
    "dimensions": { ... },
    "resources": { ... }
  },
  "memories": {
    "evaluate_skill": "/evaluate-memory",
    "write_skill": "/write-memory",
    "dimensions": { ... },
    "resources": { ... }
  },
  "agents": {
    "evaluate_skill": null,
    "write_skill": "/write-agent",
    "dimensions": { ... },
    "resources": { ... }
  }
}
```

### Schema Details

- **dimensions**: Per resource type, defines what's measured and max score per dimension
- **evaluate_skill / write_skill**: References to corresponding skills (null if none exists)
- **file_hash**: MD5/SHA of resource file for stale detection
- **grade**: Derived from total/max percentage (A/B/C/D/F scale)
- **version**: Toolkit version when evaluated

### Query Script: `.claude/scripts/evaluation-query.sh`

| Command | Output |
|---------|--------|
| `evaluation-query.sh` | List all with grade summary |
| `evaluation-query.sh stale` | Resources where file_hash differs from current |
| `evaluation-query.sh unevaluated` | Resources with no entry in evaluations.json |
| `evaluation-query.sh grade B+` | Filter by minimum grade |
| `evaluation-query.sh type skills` | Filter by resource type |

### Example Output

```
$ evaluation-query.sh stale
[skills] write-memory - hash mismatch, re-evaluate with /evaluate-skill
[hooks] secrets-guard - hash mismatch, re-evaluate with /evaluate-hook

$ evaluation-query.sh unevaluated
[skills] brainstorm-idea - not evaluated, use /evaluate-skill
[agents] code-debugger - not evaluated (no evaluate skill available)
```

## Integration

1. After running `/evaluate-*`, update evaluations.json with results
2. Before version bump, run `evaluation-query.sh stale` and `evaluation-query.sh unevaluated`
3. Query script shows which skill to use for re-evaluation

## Files to Create

| File | Purpose |
|------|---------|
| `.claude/evaluations.json` | Evaluation data store |
| `.claude/scripts/evaluation-query.sh` | Query CLI |

## Future Considerations

- Auto-update evaluations.json from evaluate-* skill output
- Add to Makefile: `make eval-check`
- Hook into wrap-up skill for release validation
