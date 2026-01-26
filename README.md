# Claude Toolkit

Curated Claude Code configuration: skills, agents, hooks, and memory templates for productive AI-assisted development.

## Quick Start

```bash
# Clone the toolkit
git clone https://github.com/yourusername/claude-toolkit.git

# Install into your project
cd /path/to/your/project
~/claude-toolkit/install.sh
```

This copies the `.claude/` directory into your project. Customize as needed.

## Concepts

| Component | What It Is | How It's Used | Lifecycle |
|-----------|------------|---------------|-----------|
| **Skill** | Triggered workflow/procedure | User invokes with `/skill-name` | Stable once written |
| **Agent** | Specialized subprocess for complex tasks | Claude spawns via Task tool | Per-task |
| **Memory** | Persistent context that survives sessions | Auto-loaded at session start or user requests | Evolves with project |
| **Hook** | Automation script triggered by events | Runs automatically on tool use or session events | Stable once written |

### Skills vs Memories

Both externalize knowledge, but serve different purposes:

- **Skills** = Step-by-step procedures. "When X happens, do Y then Z."
- **Memories** = Context and conventions. "Here's how we do things here."

A skill tells Claude *what to do*. A memory tells Claude *what to know*.

**Example:** `/write-memory` is a skill (procedure for creating memories). `essential-conventions-memory.md` is a memory (naming conventions to follow).

## What's Included

### Skills (23)

User-invocable skills activated with `/skill-name`:

| Skill | Description |
|-------|-------------|
| `analyze-idea` | Research and exploration - investigates topics, gathers evidence, generates reports |
| `brainstorm-idea` | Turn fuzzy ideas into clear designs through structured dialogue |
| `database-schema` | Design robust database schemas with normalization and indexing guidance |
| `docker-deployment` | Generate Dockerfile and docker-compose for projects |
| `draft-pr` | Generate pull request descriptions for the current branch |
| `git-worktrees` | Reference for git worktrees - setup, usage, and common pitfalls |
| `json-reader` | Read and analyze JSON files efficiently using jq |
| `list-memories` | List available memories with Quick Reference summaries |
| `mermaid-diagrams` | Create diagrams for architecture, flows, and models |
| `naming-analyzer` | Analyze and suggest better variable/function names |
| `next-steps` | Capture context before `/clear` for session continuity |
| `qa-planner` | Plan comprehensive QA testing strategy |
| `quick-review` | Fast code review focused on blockers |
| `review-plan` | Review implementation plans against quality criteria |
| `snap-back` | Reset tone when Claude drifts into sycophancy |
| `wrap-up` | Session wrap-up and handoff documentation |
| `write-hook` | Create new hooks for Claude Code |
| `write-memory` | Create new memory files following conventions |
| `write-skill` | Create new skills using test-driven documentation |
| `agent-judge` | Evaluate agent prompt quality and design |
| `skill-judge` | Evaluate skill design quality against specifications |
| `hook-judge` | Evaluate hook quality before deployment |
| `memory-judge` | Evaluate memory file quality against conventions |

### Agents (6)

Specialized agents for complex tasks:

| Agent | Description |
|-------|-------------|
| `codebase-mapper` | Explores codebase and writes structured analysis documents |
| `code-reviewer` | Pragmatic code reviewer focused on real risks |
| `code-debugger` | Investigates bugs using scientific method with persistent state |
| `goal-verifier` | Verifies work is actually complete, not just tasks checked off |
| `plan-reviewer` | Compares implementation to planning docs at milestones |
| `pattern-finder` | Documents how things are implemented - finds examples of patterns |

### Hooks (9)

Automation hooks configured in `settings.json`:

| Hook | Trigger | Purpose |
|------|---------|---------|
| `session-start.sh` | SessionStart | Loads essential memories and git context |
| `track-skill-usage.sh` | UserPromptSubmit | Logs skill invocations |
| `block-dangerous-commands.sh` | PreToolUse (Bash) | Blocks destructive commands (rm -rf /, etc.) |
| `enforce-uv-run.sh` | PreToolUse (Bash) | Ensures Python commands use `uv run` |
| `enforce-make-commands.sh` | PreToolUse (Bash) | Encourages Make targets over raw commands |
| `secrets-guard.sh` | PreToolUse (Read\|Bash) | Warns before reading .env files |
| `suggest-json-reader.sh` | PreToolUse (Read) | Suggests /json-reader for large JSON files |
| `copy-plan-to-project.sh` | PostToolUse (Write) | Copies plan files to `.planning/` |
| `track-agent-usage.sh` | PostToolUse (Task) | Logs agent spawns |

**Note:** `enforce-uv-run.sh` is Python-specific. Remove or modify for non-Python projects.

### Memory Templates (7)

Starting point for project memories in `.claude/memories/`:

| Memory | Purpose |
|--------|---------|
| `essential-conventions-code_style` | Coding conventions and style guide |
| `essential-conventions-memory` | Memory naming conventions |
| `essential-preferences-communication_style` | Communication style preferences |
| `essential-reference-commands` | CLI and Make commands reference |
| `essential-workflow-branch_development` | Branch-based development workflow |
| `essential-workflow-task_completion` | Task completion checklist |
| `philosophy-reducing_entropy` | Philosophy on reducing codebase entropy |

## Configuration

### settings.local.json

The included `settings.local.json` configures:
- Pre-approved Bash commands (`uv run`, `make`, `mkdir`, `mv`, `ls`)
- Session start hook for loading memories
- Pre-tool hooks for enforcing patterns
- Post-tool hooks for plan management

Customize permissions and hooks for your workflow.

## Customization

### Adding Skills

1. Create `.claude/skills/your-skill/SKILL.md`
2. Follow the skill template structure
3. Use `/skill-judge` to evaluate quality

### Adding Agents

1. Create `.claude/agents/your-agent.md`
2. Include frontmatter: name, description, tools, color (optional)
3. Use `/agent-judge` to evaluate quality

### Adding Memories

1. Use `/write-memory` to create properly formatted memories
2. Follow naming conventions in `essential-conventions-memory.md`

## Related Projects

- [dotfiles](https://github.com/yourusername/dotfiles) - Personal development environment (shell, git, editors)
- [python-template](https://github.com/yourusername/python-template) - Python/data engineering project scaffold

## License

MIT
