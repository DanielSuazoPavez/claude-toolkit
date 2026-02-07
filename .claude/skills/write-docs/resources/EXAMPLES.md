# write-docs Examples

Good and bad examples for both modes. Use these to calibrate output quality.

## Contents

1. [User-Docs Mode](#user-docs-mode) — README and markdown documentation
2. [Docstrings Mode](#docstrings-mode) — Inline code documentation

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
