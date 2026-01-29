---
name: read-json
description: Use when reading, querying, or analyzing JSON files. Keywords: .json, jq, JSON file, read JSON, parse JSON, query JSON, inspect JSON, extract from JSON. Uses jq for efficient querying.
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

### 3. Common Operations

| Task | Command |
|------|---------|
| Pretty-print | `jq '.' file.json` |
| Extract field | `jq '.fieldname' file.json` |
| Get keys | `jq 'keys' file.json` |
| Filter array | `jq '.[] \| select(.status=="active")' file.json` |
| Transform | `jq '{name: .user.name, age: .user.age}' file.json` |
| Count items | `jq 'length' file.json` |
| Get first N | `jq '.[0:5]' file.json` |
| Remove quotes | `jq -r '.field' file.json` |

### 4. Error Handling Patterns

```bash
# Handle missing keys (return null instead of error)
jq '.missing_key // null' file.json

# Return default value for missing keys
jq '.config.timeout // 30' file.json

# Handle null values in arrays
jq '[.items[] | select(. != null)]' file.json

# Safe nested access (won't error if intermediate is null)
jq '.data?.nested?.value' file.json

# Try/catch for potentially invalid paths
jq 'try .path.to.value catch "not found"' file.json

# Validate JSON before processing
jq empty file.json && echo "Valid JSON" || echo "Invalid JSON"

# Handle both object and array inputs
jq 'if type == "array" then .[0] else . end' file.json
```

### 5. Complex Query Examples

```bash
# Nested access with multiple conditions
jq '.users[] | select(.age > 21 and .status == "active") | .name' file.json

# Combine filters with transformation
jq '[.items[] | select(.price < 100) | {name, discounted: (.price * 0.9)}]' file.json

# Group and count
jq 'group_by(.category) | map({category: .[0].category, count: length})' file.json

# Flatten nested arrays
jq '[.departments[].employees[].name]' file.json

# Custom output formatting
jq -r '.users[] | "\(.name): \(.email)"' file.json

# Multiple filters with different outputs
jq '{total: length, active: [.[] | select(.active)] | length}' file.json

# Sort and limit
jq '[.[] | select(.score > 50)] | sort_by(.score) | reverse | .[0:10]' file.json

# Merge objects
jq '.defaults * .overrides' file.json
```

## Fallback: When jq Is Unavailable

If jq is not installed, use Python as fallback:

```bash
# Check if jq exists
which jq || echo "jq not found, using Python fallback"

# Python fallback for common operations
python3 -c "import json; print(json.dumps(json.load(open('file.json')), indent=2))"

# Get keys
python3 -c "import json; print(list(json.load(open('file.json')).keys()))"

# Extract field
python3 -c "import json; print(json.load(open('file.json'))['fieldname'])"

# Get length
python3 -c "import json; print(len(json.load(open('file.json'))))"
```

### jq vs Python Comparison

| Task | jq | Python Fallback |
|------|-----|-----------------|
| Pretty-print | `jq '.'` | `python3 -c "import json; ..."` |
| Keys | `jq 'keys'` | `.keys()` |
| Field | `jq '.field'` | `['field']` |
| Filter | `jq 'select(...)'` | List comprehension |

**Prefer jq** when available (faster, cleaner). Use Python only as fallback.

## Tool Selection

```
What do I need from this JSON?
├─ Quick structure check → jq 'keys' (fastest)
├─ Specific known path → jq '.path.to.value'
├─ Complex filtering → jq with select()
├─ jq not installed → Python fallback
└─ Need to modify file → Python (jq is read-only)
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
| **Read Tool for JSON** | Loads entire file into context | Always use jq/Python, even for small files |
| **No Length Check** | Surprised by 10K array elements | Check `length` before iterating |
