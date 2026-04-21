# Toolkit Identity

## 1. Quick Reference

**MANDATORY:** Read at session start - shapes all resource decisions.

Claude Toolkit is a **resource workshop**: the canonical place where Claude Code resources — skills, agents, hooks, and docs — are authored, refined, and distributed. Downstream projects consume these resources via `claude-toolkit sync`.

**See also:** `essential-conventions-code_style` for implementation guidelines, `relevant-toolkit-context` for context conventions, `relevant-philosophy-reducing_entropy` for curation philosophy

---

## 2. What This Is

A workshop for Claude Code resources. Resources are authored and evolved here, then flow outward to downstream projects through the sync CLI. Before the workshop existed, the same resources were copy-pasted between projects and drifted; the workshop exists so there is one canonical place they live and improve.

Not a marketplace, not a framework, not an autonomous agent system. Not an orchestrator — it doesn't coordinate downstream projects, it supplies them.

**Core traits:**
- **Workshop, not hub** — produces resources for consumers to pull; does not coordinate or command them
- **Portable resources** — synced via `claude-toolkit sync`, not tied to any single repo
- **Human-in-the-loop** — collaborative sessions, not "leave Claude running for hours." Both preference and budget drive this
- **Curated, not exhaustive** — every resource earns its place through real use, not speculative value
- **Explicit over automatic** — prefer named commands (`/skill-name`) over contextual auto-triggering, though not dogmatically

---

## 3. Downstream Projects

The workshop has two kinds of downstream projects:

- **Consumers** — pull curated resources via `claude-toolkit sync`. Most projects are consumers and nothing more.
- **Satellites** — specialist projects (one thing, done well) that both consume toolkit resources and feed specialist extensions back upstream via `suggestions-box/`. Examples: claude-sessions, aws-toolkit, schema-smith, validation-framework.

Any downstream project — consumer or satellite — can send feedback or extensions upstream through `suggestions-box/`. Satellites are peers, not children; they depend on the workshop the way any project depends on a library.

**Runtime infrastructure** (databases, long-lived state) is not authored here. The workshop produces *resources*, not runtime data stores. Global databases (`~/.claude/`) exist where they're shared across all projects; their schema and analytics logic are owned by the satellite whose niche they fit (e.g., `claude-sessions` manages session/lessons schemas). Either way, the workshop is not the owner.

---

## 4. Resource Roles

| Resource | Primary mode | Purpose |
|----------|-------------|---------|
| **Skill** | User invokes by name (`/skill-name`) | Step-by-step procedures — "do this" |
| **Hook** | Runs automatically on events | Consistent enforcement — the one place where auto-triggering is the point |
| **Agent** | Mixed — Claude spawns or user requests | Specialized subtasks, often parallelizable |
| **Doc** | Auto-loaded or on-demand | Rules, conventions, reference — "know this" |

Skills are commands, not suggestions. Hooks are guardrails, not skills. Docs inform, they don't instruct.

---

## 5. Does This Belong?

When evaluating whether to add or keep a resource:

1. **Does it solve a current gap?** — Something you've actually encountered, not a hypothetical
2. **Will you actually use it?** — Across more than one project
3. **Is the right resource type chosen?** — Command → skill, enforcement → hook, context → doc, subtask → agent
4. **Is it worth the context cost?** — Would you miss it if it were gone?
5. **Is it a resource, or runtime infrastructure?** — The workshop authors resources. Long-lived databases, analytics pipelines, or runtime state belong in a satellite, not here.

If you can't answer yes to 1–4 confidently, it's not ready. If question 5 points to runtime infrastructure, route it to the appropriate satellite instead.

Domain-specific resources (Python, Docker, AWS) are fine — as long as they reflect current work, not aspirational coverage. Project-specific config lives in the project's own `.claude/`, not here.

**Curated references** (`output/claude-toolkit/exploration/`) are the lane for "interesting but not actionable now." Don't promote to a real resource until there's a concrete use case.

---

## 6. How We Differ

**vs. Anthropic's skill-creator model:** They optimize for marketplace distribution — auto-triggering via keyword-rich descriptions, packaging, discovery. We optimize for a known set of resources invoked by name. Their description is a routing mechanism; ours is documentation.
