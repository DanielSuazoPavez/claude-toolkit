# Getting Started

You've received a `.claude/` folder — a curated configuration layer for [Claude Code](https://docs.anthropic.com/en/docs/claude-code), Anthropic's CLI tool for working with Claude in your terminal.

This toolkit adds skills (commands you invoke), agents (subtask specialists Claude uses), hooks (automatic guardrails), and docs (reference documentation that shapes behavior) on top of Claude Code. Everything is designed to work together out of the box — except hooks, which need a one-time activation step (see [Activating Hooks](#3-activating-hooks)).

---

## 1. What's in the Box

### Skills

Commands you invoke by typing `/name` in Claude Code. Think of them as repeatable procedures Claude follows step by step.

| Skill | What it does |
|-------|-------------|
| `/brainstorm-idea` | Turns a fuzzy idea into a clear design through structured Q&A |
| `/read-json` | Reads and queries JSON files using jq — handles large files safely |
| `/review-plan` | Reviews a plan against quality criteria before you approve it |
| `/wrap-up` | Finalizes a feature branch — commits, version bump, changelog |
| `/write-handoff` | Saves context before ending a session so the next one can pick up |

### Agents

Subtask specialists that Claude spawns when needed. You don't invoke these directly — Claude decides when to use them.

| Agent | What it does |
|-------|-------------|
| code-debugger | Investigates bugs methodically with persistent state across context resets |
| code-reviewer | Pragmatic code review focused on real risks, proportional to project scale |
| goal-verifier | Checks that work actually achieves its goals, not just that tasks were checked off |
| implementation-checker | Compares implementation against a plan and writes a review report |

### Hooks

Automatic guardrails that run every time Claude uses certain tools. They block dangerous actions before they happen. **Hooks require activation** — see [section 3](#3-activating-hooks).

| Hook | What it does |
|------|-------------|
| block-config-edits | Prevents modification of shell configs, SSH, and git configuration |
| block-dangerous-commands | Blocks destructive commands: `rm -rf /`, fork bombs, disk formats |
| git-safety | Enforces branch safety — blocks commits, force pushes on protected branches |
| secrets-guard | Blocks access to secret files: `.env`, SSH keys, cloud credentials, tokens |
| suggest-read-json | Suggests `/read-json` for large JSON files instead of reading them raw |

### Docs

Reference documentation in `.claude/docs/` that shapes how Claude behaves. Essential docs are loaded at the start of each session; others are read on-demand.

| Doc | What it does |
|-----|-------------|
| code_style | Code conventions: functions over classes, env vars for config, minimal interfaces |
| context | How docs and memories are organized, naming conventions |

**Edit these to match your project.** The defaults are opinionated — update them so Claude follows your conventions, not someone else's.

---

## 2. Try It: `/brainstorm-idea`

This is the "hello world" of the toolkit. It works for any project and any tech stack — all you need is a fuzzy idea.

1. Open Claude Code in your project directory
2. Type `/brainstorm-idea`
3. Describe something you've been thinking about but haven't fully defined — a feature, a refactor, an integration, anything
4. Claude will ask clarifying questions one at a time (often multiple choice) to understand the problem, audience, constraints, and success criteria
5. After a few rounds, Claude presents 2-3 approaches with trade-offs in a comparison table
6. Pick the direction you like, and Claude produces a design document summarizing the decisions

The output is a clear design you can take into plan mode (`/plan`) to start implementation, or share with your team for feedback.

**What just happened?** Skills are markdown files in `.claude/skills/` that Claude follows as procedures. You can read them, modify them, or write new ones. The skill didn't execute code — it guided Claude through a structured conversation.

---

## 3. Activating Hooks

Hook scripts exist in `.claude/hooks/`, but they're inert until you wire them up in `settings.json`. Without that configuration, Claude Code doesn't know to run them.

### Fresh setup (no existing settings)

Copy the template:

```bash
cp .claude/templates/settings.template.json .claude/settings.json
```

The template includes wiring for all hooks in this distribution, ready to go.

### Existing settings

If you already have a `.claude/settings.json`, merge the `hooks` block from `.claude/templates/settings.template.json` into your existing file. The structure looks like:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash .claude/hooks/block-dangerous-commands.sh"
          }
        ]
      }
    ]
  }
}
```

Each hook entry has a `matcher` (which Claude Code tool triggers it) and a `command` (the script to run). See the template for the full configuration.

### Customization

The template's `_env_config` section documents environment variables that hooks read. For example, `PROTECTED_BRANCHES` controls which branches `git-safety.sh` protects (default: `main` and `master`). Set these in your shell or `.envrc` — you don't need to modify the hook scripts.

### Committing settings

`settings.json` is typically committed to your repo — it defines shared guardrails for anyone using Claude Code on the project. If you need personal permission overrides (like auto-approving specific tools), use `.claude/settings.local.json` instead — that file is not committed.

### Other templates

The distribution includes two more templates in `.claude/templates/`:

- **`CLAUDE.md.template`** — Project instructions for Claude Code. Copy to your project root as `CLAUDE.md` and fill in the placeholders. This is how you tell Claude about your project's commands, structure, and conventions.
- **`mcp.template.json`** — MCP server configuration. Optional — only relevant if you use external tool servers. Disabled by default.

---

## 4. Want More?

This toolkit is curated — every resource solves a real problem that came up during actual development. If something isn't here, it's either because it wasn't needed or because a simpler approach worked better.

If you want something that's not included, talk to whoever shared this toolkit with you. They can add resources from the full toolkit or help you create project-specific ones.

Don't go hunting on GitHub for random Claude Code configurations to bolt on. The curation is the point — a small set of resources that work well together is more valuable than a large collection of things that might conflict or add noise.
