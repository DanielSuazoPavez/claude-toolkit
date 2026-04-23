---
name: read-json
metadata: { type: knowledge }
user-invocable: false
description: jq recipes for shell-quoting traps and malformed JSON. Load when writing jq pipelines with shell variables, or when jq errors on JSON with BOM/trailing commas/JSONL/truncation/embedded content.
compatibility: jq
allowed-tools: Bash(jq:*), Bash(sed:*)
---

# jq Reference

The `suggest-read-json` hook blocks the Read tool on large `.json` files and points here. This skill is background knowledge — recipes for two failure modes that cost time: shell quoting and malformed input.

## Shell Quoting for jq

jq expressions with shell variables break silently or produce wrong results.

```bash
# WRONG: double quotes inside double quotes — shell eats the inner quotes
jq ".users[] | select(.name == "alice")" file.json

# RIGHT: single-quote the jq expression
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

## Malformed JSON Handling

```bash
# Validate before processing
jq empty file.json 2>/dev/null && echo "Valid" || echo "Invalid"

# Show the exact parse error location
jq '.' file.json 2>&1 | head -5

# Trailing commas (common hand-edited JSON)
sed 's/,\s*}/}/g; s/,\s*\]/]/g' file.json | jq '.'

# JSONL (newline-delimited JSON) — NOT valid JSON but common
jq -s '.' file.jsonl          # slurp into array
jq '.' file.jsonl             # process line by line (no -s)

# JSON with BOM (Windows-created files)
sed '1s/^\xEF\xBB\xBF//' file.json | jq '.'

# Truncated JSON — extract what you can
jq -R 'try (fromjson | .key) catch empty' file.json

# JSON embedded in other output (e.g., API response with headers)
tail -1 response.txt | jq '.'
```
