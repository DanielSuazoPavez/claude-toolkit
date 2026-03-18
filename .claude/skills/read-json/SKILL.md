---
name: read-json
type: command
description: Use when reading, querying, or analyzing JSON files. Keywords: .json, jq, JSON file, read JSON, parse JSON, query JSON, inspect JSON, extract from JSON.
argument-hint: "[file-path]"
---

# JSON Reader Skill

## Core Instructions

### 1. Default to jq for JSON Operations

When you encounter a JSON file request:
- DON'T use the Read tool on JSON files
- DO use jq commands with Bash
- This applies even if the file seems small

### 2. Progressive Inspection Pattern

```bash
# Step 1: Understand structure
jq 'keys' /path/to/file.json

# Step 2: Check size/shape
jq 'length' /path/to/file.json

# Step 3: Sample data
jq '.[0:3]' /path/to/file.json  # For arrays

# Step 4: Extract what you need
jq '.specific.path' /path/to/file.json
```

### 3. Shell Quoting for jq

jq expressions with special characters break silently or produce wrong results. These patterns are the most common source of bugs.

```bash
# WRONG: double quotes inside double quotes — shell eats the inner quotes
jq ".users[] | select(.name == "alice")" file.json

# RIGHT: single-quote the jq expression, use \" or jq's own string matching
jq '.users[] | select(.name == "alice")' file.json

# Interpolating shell variables — use --arg, not string interpolation
name="alice"
# WRONG: shell expansion inside jq
jq ".users[] | select(.name == \"$name\")" file.json
# RIGHT: --arg passes variables safely
jq --arg n "$name" '.users[] | select(.name == $n)' file.json

# Multiple variables
jq --arg status "$status" --arg role "$role" \
  '.users[] | select(.status == $status and .role == $role)' file.json

# Numeric variables — use --argjson (not --arg) to avoid string coercion
jq --argjson min "$threshold" '.[] | select(.score >= $min)' file.json

# Filenames with spaces or special chars — quote the path
jq '.data' "/path/to/my file.json"
```

### 4. Malformed JSON Handling

```bash
# Validate before processing
jq empty file.json 2>/dev/null && echo "Valid" || echo "Invalid"

# Show the exact parse error location
jq '.' file.json 2>&1 | head -5

# Handle trailing commas (common hand-edited JSON)
sed 's/,\s*}/}/g; s/,\s*\]/]/g' file.json | jq '.'

# Handle JSONL (newline-delimited JSON) — NOT valid JSON but common
jq -s '.' file.jsonl          # slurp into array
jq '.' file.jsonl             # process line by line (no -s)

# Handle JSON with BOM (Windows-created files)
sed '1s/^\xEF\xBB\xBF//' file.json | jq '.'

# Truncated JSON — extract what you can
jq -R 'try (fromjson | .key) catch empty' file.json

# JSON embedded in other output (e.g., API response with headers)
tail -1 response.txt | jq '.'
```

## Tool Selection

```
What do I need from this JSON?
├─ Quick structure check → jq 'keys' (fastest)
├─ Specific known path → jq '.path.to.value'
├─ Complex filtering → jq with select()
├─ jq not installed → Python fallback
└─ Need to modify file → Python or sponge (jq is read-only)
```

| File Size | Approach |
|-----------|----------|
| < 1MB | jq or Python, either fine |
| 1-50MB | jq preferred (streaming) |
| > 50MB | `jq --stream` or `jq -c` for memory efficiency |

## Anti-Patterns

| Pattern | Problem | Fix |
|---------|---------|-----|
| **Load Full File** | Wastes tokens on structure you don't need | Use `jq 'keys'` first, then target specific paths |
| **Blind Extraction** | Guessing paths that may not exist | Explore with `keys` and samples before extracting |
| **Read Tool for JSON** | Loads entire file into context | Always use jq via Bash, even for small files |
| **No Length Check** | Surprised by 10K array elements | Check `length` before iterating |
| **Shell Interpolation in jq** | Quoting bugs, injection, wrong results | Use `--arg`/`--argjson` for all shell variables |
| **Assuming Valid JSON** | Cryptic jq errors on malformed input | Run `jq empty` first to validate |

## See Also

- `suggest-read-json` hook — PreToolUse hook that blocks Read tool on large JSON files and suggests this skill
