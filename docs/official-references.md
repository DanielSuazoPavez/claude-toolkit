# Official Claude Code Documentation Reference

Curated index of Anthropic's official Claude Code documentation. Use as the primary source when settling "is this actually supported?" questions — reverse-engineering and third-party tutorials have led us astray before.

**Canonical domain**: `code.claude.com/docs/en/` (the old `docs.anthropic.com/en/docs/claude-code/` redirects here).

## Core Documentation

| Page | URL | Covers |
|------|-----|--------|
| Overview | [/overview](https://code.claude.com/docs/en/overview) | Installation, surfaces (Terminal, VS Code, JetBrains, Desktop, Web), feature overview, provider options |
| Memory | [/memory](https://code.claude.com/docs/en/memory) | CLAUDE.md files, `.claude/rules/` (path-scoped), auto memory, `@import` syntax, `claudeMdExcludes` |
| Skills | [/skills](https://code.claude.com/docs/en/skills) | SKILL.md authoring, frontmatter fields, `$ARGUMENTS` substitution, dynamic context (`` !`cmd` ``), discovery budget |
| Sub-agents | [/sub-agents](https://code.claude.com/docs/en/sub-agents) | `.claude/agents/` definitions, built-in types (Explore, Plan, general-purpose), frontmatter, agent auto-memory |
| Hooks reference | [/hooks](https://code.claude.com/docs/en/hooks) | 7 hook types, 25+ events, config locations, env vars available in hooks |
| Hooks guide | [/hooks-guide](https://code.claude.com/docs/en/hooks-guide) | Tutorial companion — practical examples, first hook setup, prompt/agent-based hooks |
| Plugins | [/plugins](https://code.claude.com/docs/en/plugins) | Plugin packaging, `plugin.json` manifest, namespaced skills, marketplace submission |
| Settings | [/settings](https://code.claude.com/docs/en/settings) | All settings files, managed policy, JSON schema, permissions, sandbox, env vars |
| MCP | [/mcp](https://code.claude.com/docs/en/mcp) | MCP server config (`.mcp.json`, `~/.claude.json`), transports (stdio/http/sse), tool naming (`mcp__<server>__<tool>`) |
| CLI reference | [/cli-reference](https://code.claude.com/docs/en/cli-reference) | 60+ CLI flags — `--agent`, `--worktree`, `--json-schema`, `--max-turns`, `--system-prompt`, etc. |

## SDK & Integrations

| Page | URL | Covers |
|------|-----|--------|
| Agent SDK | [/agent-sdk/overview](https://code.claude.com/docs/en/agent-sdk/overview) | Python (`claude-agent-sdk`) and TypeScript (`@anthropic-ai/claude-agent-sdk`), `query()` API, built-in tools, hooks, subagents, sessions |
| GitHub Actions | [/github-actions](https://code.claude.com/docs/en/github-actions) | `anthropics/claude-code-action@v1`, `@claude` trigger, Bedrock/Vertex support |
| VS Code | [/vs-code](https://code.claude.com/docs/en/vs-code) | Extension features, inline diffs, IDE MCP server (`mcp__ide__getDiagnostics`), extension settings |
| JetBrains | [/jetbrains](https://code.claude.com/docs/en/jetbrains) | JetBrains plugin (separate from VS Code docs) |
| Enterprise deployment | [/bedrock-vertex](https://code.claude.com/docs/en/bedrock-vertex) | Bedrock, Vertex AI, Microsoft Foundry, proxy/gateway config |

## Reference Pages

| Page | URL | Covers |
|------|-----|--------|
| **Environment variables** | [/env-vars](https://code.claude.com/docs/en/env-vars) | **180+ official env vars** — authoritative list of platform-owned variables |
| **Commands** | [/commands](https://code.claude.com/docs/en/commands) | All built-in slash commands and bundled skills |
| Security | [/security](https://code.claude.com/docs/en/security) | Permission model, sandbox, prompt injection protections, MCP security |
| Troubleshooting | [/troubleshooting](https://code.claude.com/docs/en/troubleshooting) | Diagnostic commands (`/doctor`, `/heapdump`), common issues |
| Machine-readable index | [/llms.txt](https://code.claude.com/docs/llms.txt) | Full doc index in llms.txt format |

## Key Platform Environment Variables

From the official [env-vars](https://code.claude.com/docs/en/env-vars) page — the subset most relevant to toolkit resource authoring:

| Variable | Context | Purpose |
|----------|---------|---------|
| `CLAUDE_PROJECT_DIR` | Hooks | Project root directory |
| `CLAUDE_ENV_FILE` | SessionStart, CwdChanged, FileChanged hooks | Write `export` statements for persistent env vars |
| `CLAUDE_CONFIG_DIR` | General | Override `~/.claude` location |
| `CLAUDE_SESSION_ID` | Skills (via `${CLAUDE_SESSION_ID}`) | Current session identifier |
| `CLAUDE_SKILL_DIR` | Skills (via `${CLAUDE_SKILL_DIR}`) | Directory of the current SKILL.md |
| `CLAUDE_PLUGIN_ROOT` | Plugins | Plugin directory root |
| `CLAUDE_PLUGIN_DATA` | Plugins | Plugin data directory |
| `CLAUDE_CODE_REMOTE` | General | `"true"` in cloud/web environments |
| `CLAUDECODE` | Shell | Set to `1` in all Claude Code shell environments |
| `CLAUDE_CODE_SIMPLE` | General | Minimal/bare mode flag |
| `CLAUDE_CODE_DISABLE_AUTO_MEMORY` | General | Disable auto memory |
| `CLAUDE_CODE_DISABLE_CLAUDE_MDS` | General | Prevent loading CLAUDE.md files |
| `SLASH_COMMAND_TOOL_CHAR_BUDGET` | Skills | Override skill description budget (default: 1% of context window) |

## Gaps the Toolkit Fills

Official documentation defines these extension points but does not cover the patterns the toolkit builds on top of them:

**No `.claude/docs/` convention.** The official patterns are `.claude/rules/` (path-scoped instructions) and CLAUDE.md (global instructions). Rules scope by *file path* (`paths: "src/**/*.ts"`) — there's no mechanism for *topic-scoped* reference that loads based on semantic relevance. The toolkit's `essential-`/`relevant-` split with `/list-docs` discovery fills this gap.

**No tiered context loading.** Official rules are binary: load unconditionally or load when a file-path glob matches. The toolkit adds Quick Reference extraction (load a summary at session start, full doc on demand) — a middle ground between "always in context" and "never loaded."

**No skill authoring guidance beyond the spec.** The `/skills` page documents the SKILL.md format but doesn't cover design patterns — progressive disclosure, when to use `agent` delegation, how to structure multi-step workflows. The toolkit's `/create-skill` and `/evaluate-skill` fill this.

**No agent design guidance beyond the spec.** The `/sub-agents` page documents frontmatter fields but doesn't cover behavioral design — when to use agents vs skills, how to scope tool access, testing patterns. The toolkit's `/create-agent` and `/evaluate-agent` fill this.

**No hook design guidance beyond the reference.** The `/hooks` reference documents events and config, but the `/hooks-guide` is a basic tutorial. The toolkit's `/create-hook` and `/evaluate-hook` cover the match/check pattern, dual-mode triggers, and hook testing.

## Terminology Collisions

**"Memories"**: Anthropic's auto-memory feature (`~/.claude/projects/<project>/memory/MEMORY.md`) landed after the toolkit's `.claude/memories/` convention. Different mechanisms — the toolkit's memories are project-checked-in organic context, while Anthropic's are machine-local auto-generated notes. The `rename-claude-docs-to-conventions` backlog task (P3) tracks potential renaming to reduce confusion.

**"Rules" vs "Docs"**: Official `.claude/rules/` are *path-scoped instructions* — closer to the toolkit's nested CLAUDE.md files (`cli/CLAUDE.md`, `tests/CLAUDE.md`) than to `.claude/docs/`. The toolkit's docs are *topic-scoped reference* with tiered loading, which has no official equivalent.

**"Custom commands" vs "Skills"**: The official docs frame skills as "custom slash commands." The toolkit treats skills as a first-class authoring surface with evaluation, lifecycle management, and design patterns beyond the "custom command" framing.

## Upstream Watch

Things to monitor in the official docs that may affect toolkit design:

- **Skill auto-invocation reliability** — currently `relevant-*` docs are conceptually similar to auto-invoked skills, but we've found auto-invocation unreliable enough to build `/list-docs` as the discovery layer
- **`.claude/rules/` evolution** — if rules gain topic-scoping or budget-aware loading, the gap with `.claude/docs/` narrows
- **Skill-creator / Claude Cowork** — not documented yet, but seen in Claude Cowork sessions; full UX with HTML rendering, A/B testing, multiple feedback rounds — a reference point for `/create-skill` evolution
- **Platform env var registry** — the `/env-vars` page is the authoritative source for confirming whether a variable name is platform-owned (relevant to `env-var-rename-bare-namespaces` task)
