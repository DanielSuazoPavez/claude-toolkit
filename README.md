# Claude Toolkit

Curated Claude Code configuration: skills, agents, hooks, and docs for productive AI-assisted development.

## Quick Start

```bash
# Clone the toolkit
git clone https://github.com/yourusername/claude-toolkit.git

# Add to PATH (makes claude-toolkit available in all shells, including non-interactive)
ln -s ~/claude-toolkit/bin/claude-toolkit ~/.local/bin/claude-toolkit

# Sync into your project
cd /path/to/your/project
claude-toolkit sync
```

This syncs the `.claude/` directory into your project. Only files listed in `.claude/MANIFEST` are copied — dev-only files stay in the toolkit. Customize as needed.

## CLI Usage

The `claude-toolkit` CLI manages toolkit distribution and updates.

```bash
# Show help
claude-toolkit --help

# Sync toolkit updates to a project
claude-toolkit sync                          # Current directory
claude-toolkit sync /path/to/project         # Specific project
claude-toolkit sync --dry-run                # Preview changes
claude-toolkit sync --only skills,hooks      # Sync specific categories

# Send a resource from another project to suggestions-box
claude-toolkit send .claude/skills/my-skill/SKILL.md --type skill --project myapp
```

### Sync Categories

When syncing, files are grouped by category for selective updates:
- **skills** - User-invocable workflows
- **agents** - Specialized task subprocesses
- **hooks** - Event-driven automation scripts
- **docs** - Prescriptive rules and reference documentation
- **templates** - Project scaffolding files
- **scripts** - Internal utility scripts

### Version Tracking

Sync uses semantic versioning to track updates:
- `VERSION` file in toolkit root
- `.claude-toolkit-version` in target projects
- `.claude-toolkit-ignore` for project-specific exclusions

## Concepts

| Component | What It Is | How It's Used | Lifecycle |
|-----------|------------|---------------|-----------|
| **Skill** | Triggered workflow/procedure | User invokes with `/skill-name` | Stable once written |
| **Agent** | Specialized subprocess for complex tasks | Claude spawns via Task tool | Per-task |
| **Doc** | Rules, conventions, reference documentation | Auto-loaded (`essential-*`) or on-demand (`relevant-*`) | Stable, rarely changes |
| **Memory** | Organic context, preferences, ideas | User creates directly in `.claude/memories/` | Evolves with project |
| **Hook** | Automation script triggered by events | Runs automatically on tool use or session events | Stable once written |

### Skills vs Docs vs Memories

Both externalize knowledge, but serve different purposes:

- **Skills** = Step-by-step procedures. "When X happens, do Y then Z."
- **Docs** = Rules, conventions, and reference documentation. "Here's how we do things here."
- **Memories** = Organic context, preferences, ideas. Unstructured files in `.claude/memories/`.

A skill tells Claude *what to do*. A doc tells Claude *what to know*.

**Example:** `/create-docs` is a skill (procedure for creating docs). `relevant-toolkit-context.md` is a doc (naming conventions to follow).

## What's Included

| Resource | Count | Examples |
|----------|-------|---------|
| **Skills** | 32 | `/brainstorm-idea`, `/draft-pr`, `/refactor`, `/learn` |
| **Agents** | 7 | `code-reviewer`, `code-debugger`, `pattern-finder` |
| **Hooks** | 10 | git safety, secrets guard, dangerous command blocking |
| **Memory templates** | 11 | code style, communication style, testing conventions |

Skills cover workflow, code quality, design, development tools, and toolkit development. Hooks cover safety (git, secrets, destructive commands) and convention enforcement (uv, make targets). Some hooks are Python-specific — remove or modify for other stacks.

For full listings with status and details, see [`docs/indexes/`](docs/indexes/).

## Dependencies

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) — the CLI this toolkit extends
- `jq` — JSON processing in hooks and skills (`/read-json`, session-start, evaluations)
- `sqlite3` — lesson storage and retrieval (`/learn`, `surface-lessons` hook)
- `bash` — all hooks and scripts target bash
- `make` — test runner and common task targets
- `uv` — Python dependency management (Python-specific hooks expect this)

## Configuration

### settings.local.json

Per-project configuration (gitignored). Configures:
- Pre-approved Bash commands to reduce permission prompts (`uv run`, `make`, `git`, etc.)
- MCP server enablement
- UI preferences

Hooks are configured in `settings.json` (committed, shared).

## Design Philosophy

See [`.claude/docs/relevant-project-identity.md`](.claude/docs/relevant-project-identity.md) for the toolkit's identity document — what it is, what it isn't, and how to evaluate whether a new resource belongs.

See also [`.claude/docs/relevant-philosophy-reducing_entropy.md`](.claude/docs/relevant-philosophy-reducing_entropy.md) for the curation philosophy — why less is more, and how to keep the toolkit lean.

## License

MIT
