# Permissions Configuration Convention

## 1. Quick Reference

**ONLY READ WHEN:**
- Adding, moving, or reviewing permission rules in settings
- User asks to allow/deny a command or tool
- Configuring a new project that consumes the toolkit
- Debugging why a command is being prompted or blocked

Two-tier permissions: toolkit-level in `settings.json` (globally safe, synced), project-level in `settings.local.json` (per-project trust, gitignored).

**See also:** `relevant-toolkit-hooks_config` for hook details, `dist/base/templates/settings.template.json` as canonical reference

---

## 2. Two-Tier Architecture

### Toolkit Level — `settings.json` (committed, synced)

Contains only **globally safe** permissions — commands that are safe in any project, any context.

**What belongs here:**
- Read-only commands: `ls`, `find`, `cat`, `head`, `tail`, `wc`, `diff`, `grep`, `echo`
- Safe filesystem: `mkdir`, `touch`
- Safe tools: `jq`, `make`
- Safe git subcommands: `status`, `log`, `diff`, `show`, `blame`, `rev-parse`, `fetch`, `stash`, `add`, `rm`, `checkout`, `switch`, `commit`
- Hook/script execution: `.claude/hooks/*`, `.claude/scripts/*`
- Read-only tool access: `Glob(**)`, `Grep(**)`, `Read(/**)`
- Output directory writes: `Write(/output/claude-toolkit/**)`, `Edit(/output/claude-toolkit/**)`

**What does NOT belong here:**
- Project-specific commands (`npm`, `poetry`, `cargo`, `docker`)
- Filesystem mutation beyond output dir (`mv`, `cp`, `rm`)
- MCP tool permissions
- Skill-specific permissions
- Anything requiring project-specific trust judgment

### Project Level — `settings.local.json` (gitignored, per-machine)

Contains **project-specific trust decisions** that vary by project.

**What belongs here:**
- Project tooling: `npm run`, `cargo test`, `docker compose`
- Filesystem mutation: `mv`, `cp`
- MCP server tools
- Skill permissions
- Any command that's safe in *this* project but not universally

---

## 3. Hook Layer

Hooks complement static rules for cases they can't handle.

| Hook | Type | Purpose |
|------|------|---------|
| `approve-safe-commands.sh` | PermissionRequest | Auto-approves chained commands (`&&`, `\|\|`, `;`, `\|`) when ALL subcommands match safe prefixes |
| `block-dangerous-commands.sh` | PreToolUse (deny) | Blocks destructive patterns (`rm -rf /`, fork bombs, disk formats) |
| `block-config-edits.sh` | PreToolUse (deny) | Blocks writes to shell configs, SSH, git config |
| `secrets-guard.sh` | PreToolUse (deny) | Blocks reading `.env`, credential files |
| `git-safety.sh` | PreToolUse (deny) | Enforces protected branch safety |

**Key design:** The `approve-safe-commands` hook reads `settings.json` `permissions.allow` directly via the shared `lib/settings-permissions.sh` loader. No drift possible — `settings.json` is the single source of truth. (Only `cd` is hardcoded as a small `ALWAYS_SAFE` carve-out, since shell builtins can't appear in the harness's permission system.)

---

## 4. Evaluation Order

```
1. PreToolUse hooks (allow, deny, or pass through)
2. Deny rules (always win)
3. Ask rules (force prompt)
4. Allow rules (auto-approve)
5. Default (prompt user)
```

Scope precedence (highest → lowest):
1. Managed settings (org-level)
2. Command-line arguments
3. `settings.local.json` (per-machine)
4. `settings.json` (shared)
5. `~/.claude/settings.json` (user global)

Allow/deny arrays **merge** across scopes. A deny at any level blocks regardless of allows.

---

## 5. For Synced Projects

`dist/base/templates/settings.template.json` is the canonical reference. When a project runs `claude-toolkit sync`, it receives this template's permissions and hooks.

Projects customize by adding to `settings.local.json` — they should never modify the synced `settings.json` permissions directly, as those will be overwritten on next sync.

---

## 6. Decision Guide — Where Does This Permission Go?

```
Is this command safe in ANY project?
├─ Yes → Add to settings.json allow list. The approve-safe-commands hook
│        picks it up automatically on next session via the shared
│        lib/settings-permissions.sh loader.
└─ No  → Is it dangerous in ALL projects?
    ├─ Yes → Deny hook (block-dangerous-commands.sh or similar)
    └─ No  → settings.local.json in each project
```
