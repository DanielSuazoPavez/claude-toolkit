# Skill & Agent Frontmatter Reference

## 1. Quick Reference

**ONLY READ WHEN:**
- Creating or modifying skills/slash commands or agents
- Evaluating skill/agent quality (frontmatter validation)
- Choosing which model to assign to an agent or skill
- Working on `skill-frontmatter-type-rename` backlog item

Official supported YAML frontmatter fields for Claude Code skills and agents.

**Last verified:** 2026-03-20

**See also:** `relevant-toolkit-hooks_config` for hook configuration

---

## 2. Two-Layer Frontmatter Model

Claude Code skills implement the [Agent Skills open standard](https://agentskills.io/specification), shared with Cursor, Gemini CLI, Copilot, Goose, etc. Claude Code adds its own extension fields on top.

**Known bug:** VS Code extension validator ([#25380](https://github.com/anthropics/claude-code/issues/25380)) only recognizes base Agent Skills fields and flags Claude Code extension fields as unsupported — even though they work fine.

### Agent Skills Standard Fields (base layer)

| Field | Required | Description |
|-------|----------|-------------|
| `name` | Yes | Max 64 chars, lowercase + hyphens |
| `description` | Yes | Max 1024 chars |
| `license` | No | License name or file reference |
| `compatibility` | No | Environment requirements |
| `metadata` | No | Arbitrary string-to-string map (author, version, tags). Informational only — no behavioral effect. |
| `allowed-tools` | No* | Comma-separated tool list. Required for command skills in this toolkit. Supports patterns: `Bash(git:*)`, `Bash(jq:*)`. Knowledge skills don't need it. |

### Claude Code Skill Extension Fields

| Field | Required | Description |
|-------|----------|-------------|
| `argument-hint` | No | Hint shown during autocomplete, e.g. `[issue-number]`. |
| `disable-model-invocation` | No | `true` prevents Claude from auto-loading. Default: `false`. |
| `user-invocable` | No | `false` hides from `/` menu. Default: `true`. |
| `model` | No | Model override: `sonnet`, `opus`, `haiku`. |
| `context` | No | Set to `fork` to run in a forked subagent context. |
| `agent` | No | Subagent type when `context: fork`. |
| `hooks` | No | Hooks scoped to this skill's lifecycle. |

### Invocation control

| Frontmatter | User can invoke | Claude can invoke | Context loading |
|-------------|-----------------|-------------------|-----------------|
| (default) | Yes | Yes | Description always loaded, full content on invoke |
| `disable-model-invocation: true` | Yes | No | Description not in context |
| `user-invocable: false` | No | Yes | Description always loaded |

### String substitutions

`$ARGUMENTS`, `$ARGUMENTS[N]`, `$N`, `${CLAUDE_SESSION_ID}`, `${CLAUDE_SKILL_DIR}`

## 3. Agent/Subagent Frontmatter (12 fields)

**Source:** [code.claude.com/docs/en/sub-agents](https://code.claude.com/docs/en/sub-agents)

Only `name` and `description` are required.

| Field | Required | Description |
|-------|----------|-------------|
| `name` | Yes | Unique identifier, lowercase letters and hyphens. |
| `description` | Yes | When Claude should delegate to this subagent. |
| `tools` | No | Tool allowlist. Inherits all if omitted. |
| `disallowedTools` | No | Tool denylist. |
| `model` | No | `sonnet`, `opus`, `haiku`, or `inherit` (default). |
| `permissionMode` | No | `default`, `acceptEdits`, `dontAsk`, `bypassPermissions`, `plan`. |
| `maxTurns` | No | Maximum agentic turns before stop. |
| `skills` | No | Skills to preload (full content injected at startup). |
| `mcpServers` | No | MCP servers available to this subagent. |
| `hooks` | No | Lifecycle hooks scoped to this subagent. |
| `memory` | No | Persistent scope: `user`, `project`, or `local`. |
| `background` | No | `true` to always run as background task. |
| `isolation` | No | `worktree` for isolated git worktree copy. |

## 4. Key Differences: Skills vs Agents

| Aspect | Skills | Agents |
|--------|--------|--------|
| Tool restriction | `allowed-tools` (string or array) | `tools` (allowlist) + `disallowedTools` (denylist) |
| Identity | `name` optional (defaults to dir name) | `name` required |
| Model default | Inherits from conversation | `inherit` |
| Unique to skills | `argument-hint`, `disable-model-invocation`, `user-invocable`, `context`, `agent`, `license`, `compatibility`, `metadata` | — |
| Unique to agents | — | `disallowedTools`, `permissionMode`, `maxTurns`, `skills`, `mcpServers`, `memory`, `background`, `isolation` |

## 5. Model Selection Guide

Use `model` frontmatter to match cost/capability to the task. Default is `inherit` (uses whatever the session runs).

### When to use each model

| Model | Use when | Examples |
|-------|----------|---------|
| **opus** | Deep reasoning, nuanced judgment, multi-step hypothesis testing | `code-debugger`, `proposal-reviewer`, `goal-verifier` |
| **sonnet** | Structured search, comparison, checklist work, pattern matching | `code-reviewer`, `codebase-explorer`, `pattern-finder`, `implementation-checker` |
| **haiku** | Simple, fast, high-volume tasks | Linting checks, format validation |
| **inherit** | Task complexity varies or matches parent session | Most skills (run inline) |

### Decision heuristic

```
Does the task require nuanced judgment or creative reasoning?
├─ Yes → opus
└─ No → Is it structured search/compare/checklist work?
    ├─ Yes → sonnet
    └─ No → Is it simple and high-volume?
        ├─ Yes → haiku
        └─ No → inherit
```

### Skills vs Agents

- **Agents**: Model frontmatter applies directly — agent runs as subagent with that model.
- **Skills**: Model only applies if skill runs in its own context (`context: fork`). Inline skills inherit the session model regardless of frontmatter.

---

## 6. Notes

- `type` is **not** a supported field in either layer. Our `type: knowledge|command` should be removed.
- However, the VS Code warning about `type` is partly the validator bug (#25380) — it flags *all* non-standard fields, including valid Claude Code extensions.
- `metadata` could theoretically replace `type` as `metadata: { type: knowledge }`, but since it has no behavioral effect, it's just documentation.
- Agent `--agents` CLI flag accepts JSON with same fields plus `prompt` (equivalent to markdown body).
