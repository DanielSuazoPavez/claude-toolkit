# Toolkit Identity

## 1. Quick Reference

**MANDATORY:** Read at session start - shapes all resource decisions.

Claude Toolkit is a personal, curated Claude Code configuration — skills, agents, hooks, and memories — portable across projects, designed for human-in-the-loop workflows.

**See also:** `essential-conventions-code_style` for implementation guidelines, `relevant-toolkit-memory` for memory conventions, `relevant-philosophy-reducing_entropy` for curation philosophy

---

## 2. What This Is

A personal toolkit of Claude Code resources that make collaborative development sessions more productive. Not a marketplace, not a framework, not an autonomous agent system.

**Core traits:**
- **Portable across projects** — synced via `claude-toolkit sync`, not tied to any single repo
- **Human-in-the-loop** — collaborative sessions, not "leave Claude running for hours." Both preference and budget drive this
- **Curated, not exhaustive** — every resource earns its place through real use, not speculative value
- **Explicit over automatic** — prefer named commands (`/skill-name`) over contextual auto-triggering, though not dogmatically

---

## 3. Resource Roles

| Resource | Primary mode | Purpose |
|----------|-------------|---------|
| **Skill** | User invokes by name (`/skill-name`) | Step-by-step procedures — "do this" |
| **Hook** | Runs automatically on events | Consistent enforcement — the one place where auto-triggering is the point |
| **Agent** | Mixed — Claude spawns or user requests | Specialized subtasks, often parallelizable |
| **Memory** | Auto-loaded or on-demand | Cross-session context — "know this" |

Skills are commands, not suggestions. Hooks are guardrails, not skills. Memories inform, they don't instruct.

---

## 4. Does This Belong?

When evaluating whether to add or keep a resource:

1. **Does it solve a current gap?** — Something you've actually encountered, not a hypothetical
2. **Will you actually use it?** — Across more than one project
3. **Is the right resource type chosen?** — Command → skill, enforcement → hook, context → memory, subtask → agent
4. **Is it worth the context cost?** — Would you miss it if it were gone?

If you can't answer yes to 1-3 confidently, it's not ready.

Domain-specific resources (Python, Docker, AWS) are fine — as long as they reflect current work, not aspirational coverage. Project-specific config lives in the project's own `.claude/`, not here.

**Curated references** (`output/claude-toolkit/exploration/`) are the lane for "interesting but not actionable now." Don't promote to a real resource until there's a concrete use case.

---

## 5. How We Differ

**vs. Anthropic's skill-creator model:** They optimize for marketplace distribution — auto-triggering via keyword-rich descriptions, packaging, discovery. We optimize for a known set of resources invoked by name. Their description is a routing mechanism; ours is documentation.
