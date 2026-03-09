# write-docs Examples

Worked examples and good/bad comparisons for both modes.

## Contents

1. [Worked Example](#worked-example-gap-analysis-to-documentation) — End-to-end flow
2. [User-Docs Mode](#user-docs-mode) — README and markdown documentation
3. [Docstrings Mode](#docstrings-mode) — Inline code documentation

---

## Worked Example: Gap Analysis to Documentation

A user asks: "Document the CLI for my project." Here's the flow from gap analysis through writing and verification.

**Step 1-2: Discovery and gap analysis output:**

```markdown
## Gap Analysis: myapp CLI

### Existing Docs
- `README.md` — has install section, CLI section lists 2 of 4 subcommands
- No standalone CLI reference

### Gaps Found
1. [OUTDATED] README shows `myapp init --template` but code removed `--template` in v2.0
2. [GAP] `myapp migrate` and `myapp validate` subcommands undocumented
3. [MISSING] No exit code documentation (CI users need this)

### Recommended Actions
- [ ] Fix README CLI section (remove dead `--template` flag)
- [ ] Add `migrate` and `validate` to CLI reference
- [ ] Document exit codes

Proceed with these?
```

**Step 3: Style detection** — existing README uses casual tone, `##` for sections, code blocks with output comments.

**Step 4: Write** — after user confirms, update README CLI section. Every flag comes from reading `cli.py`'s argument parser. Every exit code comes from tracing `sys.exit()` calls.

**Step 5: Verify** — staleness-risk prioritization:
1. Code examples: mentally trace `myapp migrate --dry-run` against the handler
2. Parameter list: confirm `--dry-run` and `--target` exist in argparse definition
3. Exit codes: trace each `sys.exit()` call to confirm codes 0, 1, 2 match documented values
4. File path `config/migrations/`: confirm directory exists in project structure

---

## User-Docs Mode

### Good: README Section

The function `send_notification` exists in `src/notify.py` and accepts `channel`, `message`, and optional `urgency` parameter.

```markdown
## Notifications

Send notifications to configured channels.

### Quick Start

```python
from myapp.notify import send_notification

send_notification("slack", "Deploy complete")
```

### API

#### `send_notification(channel, message, urgency="normal")`

Sends a message to the specified channel.

- **channel** (`str`): Target channel. Supported: `"slack"`, `"email"`, `"webhook"`.
- **message** (`str`): Notification body. Markdown supported for Slack.
- **urgency** (`str`): `"normal"` (default) or `"critical"`. Critical sends immediately, bypassing batching.

Raises `ChannelNotFoundError` if channel isn't configured in `config.yml`.

```python
# Critical alert — bypasses 5-minute batch window
send_notification("slack", "DB connection pool exhausted", urgency="critical")
```

See `docs/channels.md` for channel configuration.
```

**Why this works:**
- Quick start gets users running in seconds
- Parameters documented from actual function signature
- Exception behavior verified against code
- Cross-references related doc instead of duplicating channel setup
- Example shows a non-obvious behavior (batch bypass)

### Bad: README Section (Same Function)

```markdown
## Notifications Module

The notifications module provides a comprehensive notification system that enables
your application to send notifications across multiple channels. It is designed to
be flexible and extensible, supporting various notification backends.

### Overview

Notifications are an important part of any application. This module makes it easy
to notify users and systems about important events.

### Usage

```python
from myapp.notify import send_notification

send_notification("slack", "hello")
```

### Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| channel | string | The channel to send to |
| message | string | The message |
| urgency | string | The urgency level |
| retry_count | int | Number of retries |
| template_id | string | Template to use |
```

**What's wrong:**
- Filler intro ("comprehensive", "flexible and extensible") adds no information
- `retry_count` and `template_id` don't exist in the actual function — **fabricated parameters**
- No mention of valid values for `channel` or `urgency`
- No exception behavior documented
- Example is trivial, doesn't show any real usage pattern
- No cross-references

---

### Good: API Reference (Partial)

Documenting a CLI tool with subcommands, verified against the actual argument parser in `cli.py`.

```markdown
## CLI Reference

### `myapp scan <path>`

Scans a directory for configuration files and reports issues.

```bash
myapp scan ./config/
# Output:
# Found 3 config files
# config/db.yml .......... OK
# config/auth.yml ........ WARN: deprecated key "secret_key"
# config/cache.yml ....... OK

myapp scan ./config/ --format json
# Outputs JSON array of results (useful for CI)
```

**Options:**

| Flag | Default | Description |
|------|---------|-------------|
| `--format` | `text` | Output format: `text` or `json` |
| `--strict` | off | Exit code 1 on warnings (not just errors) |

**Exit codes:** `0` success, `1` errors found (or warnings in strict mode), `2` invalid path.
```

**Why this works:**
- Shows actual output the user will see
- Documents exit codes (critical for CI usage)
- `--format json` example shows a real use case, not just the flag

### Bad: API Reference (Same CLI)

```markdown
## CLI

Run `myapp scan` to scan things.

### Options

- `--format`: Set the format
- `--strict`: Enable strict mode
- `--verbose`: Show more output
- `--quiet`: Show less output
```

**What's wrong:**
- No example output — user doesn't know what to expect
- `--verbose` and `--quiet` don't exist — **fabricated flags**
- Descriptions restate the flag name ("Set the format" for `--format`)
- No exit codes documented
- "Scan things" — what things?

---

## Docstrings Mode

### Good: Python Docstring (Google Style)

Actual function in `src/cache.py`:

```python
def invalidate(self, pattern: str, *, cascade: bool = False) -> int:
    """Remove cache entries matching a glob pattern.

    Args:
        pattern: Glob pattern to match keys (e.g., "user:*", "session:abc*").
        cascade: If True, also invalidate entries that depend on matched keys
            via the dependency graph in `cache_deps.json`.

    Returns:
        Number of entries removed.

    Raises:
        InvalidPatternError: If pattern contains unsupported glob syntax.
            Supported: *, ?. Not supported: **, {a,b}.
    """
```

**Why this works:**
- Shows concrete pattern examples in the `pattern` description
- `cascade` explains the mechanism (dependency graph) and where it's configured
- Documents what glob syntax IS and ISN'T supported — non-obvious constraint
- Return value is specific (count, not bool)

### Bad: Python Docstring (Same Function)

```python
def invalidate(self, pattern: str, *, cascade: bool = False) -> int:
    """Invalidate cache entries.

    This method invalidates cache entries that match the given pattern.
    It supports glob-style pattern matching for flexible cache invalidation.

    Args:
        pattern: The pattern to use for matching.
        cascade: Whether to cascade the invalidation.

    Returns:
        int: The result of the invalidation operation.
    """
```

**What's wrong:**
- First two sentences say the same thing as the function name
- `pattern` description doesn't show what patterns look like
- `cascade` doesn't explain what cascading means in this context
- "The result of the invalidation operation" — what result? A count? A bool?
- No exception documentation
- No mention of supported/unsupported glob syntax

---

### Good: JavaScript JSDoc

```javascript
/**
 * Rate-limits function calls using a token bucket algorithm.
 *
 * @param {Function} fn - Function to wrap. Must return a Promise.
 * @param {Object} opts
 * @param {number} opts.maxBurst - Max calls allowed in a burst (bucket size).
 * @param {number} opts.perSecond - Sustained calls per second (refill rate).
 * @returns {Function} Wrapped function that queues calls when rate exceeded.
 *   Queued calls resolve in order. Rejects with `RateLimitError` after 30s in queue.
 *
 * @example
 * const limitedFetch = rateLimit(fetch, { maxBurst: 10, perSecond: 2 });
 * const res = await limitedFetch("/api/data"); // queues if over limit
 */
```

### Bad: JavaScript JSDoc (Same Function)

```javascript
/**
 * Rate limits a function.
 *
 * @param {Function} fn - The function.
 * @param {Object} opts - The options.
 * @returns {Function} The rate limited function.
 */
```

**What's wrong:**
- Parameters described as "The function", "The options" — restates the type
- No mention of algorithm, burst vs sustained rate, or queuing behavior
- No example showing real usage
- Missing: what happens when limit is exceeded? Throws? Queues? Drops?
