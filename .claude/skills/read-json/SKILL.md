---
name: read-json
description: Use when reading, inspecting, or analyzing any JSON file. Uses jq for efficient querying instead of loading entire files into context. Activate this skill whenever a user asks to read, view, explore, or extract data from a .json file.
---

# JSON Reader Skill

## Purpose

When working with JSON files, use jq for efficient, targeted querying instead of the Read tool.

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

## When to Use This Skill

- Analyzing JSON configuration files
- Extracting data from JSON APIs
- Filtering large JSON datasets
- Transforming JSON structures
- Validating JSON format
- Any JSON inspection/manipulation task

## Advantages

- Handles large files efficiently (doesn't load entire file into context)
- Precise targeting with jq selectors
- Composable with other Unix tools
- Clear, readable syntax
- Industry-standard tool

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
