# Execution Conventions

## 1. Quick Reference

**MANDATORY:** Read at session start — affects every command Claude runs.

Rules of thumb when running shell or git commands:

- **No sudo.** Provide commands for the user to run when elevated privileges are needed.
- **Relative paths from project root** (`.claude/scripts/foo.sh`) — not `cd` or absolute (`/home/.../foo.sh`).
- **No `git -c` unless the user asks for it** — per-invocation config overrides are almost always a smell of bypassing a hook or signing requirement.
- **No `--no-verify`, `--no-gpg-sign`, or other hook/safety bypasses** unless the user explicitly asks.

---

## 2. Sudo

Claude has no sudo access in this environment.

When a task needs elevated privileges (installing system packages, editing protected files, restarting services), do not attempt the command. Instead, **provide the exact shell command for the user to run manually**, and continue with whatever else you can do without it.

---

## 3. Paths

Run commands with paths relative to the project root.

| Pattern | Use |
|---------|-----|
| `bash .claude/scripts/foo.sh` | ✓ Relative from project root |
| `cd .claude/scripts && bash foo.sh` | ✗ Avoid `cd` — breaks permission patterns |
| `bash /home/hata/projects/.../foo.sh` | ✗ Absolute paths break across machines and miss permission allowlists |

The harness sets the working directory to the project root; rely on it.

If you genuinely need to run something from a subdirectory (e.g., a tool that requires its CWD), prefer `--directory`/`--cwd` flags over `cd`. If neither is available and `cd` is the only option, quote-protect and chain with `&&` so the working directory doesn't leak into the next command.

---

## 4. Git command hygiene

### `git -c` — almost never needed

`git -c key=value <command>` overrides config for one invocation. Legitimate uses are rare:

- The user explicitly asks for an override (e.g., `git -c user.signingkey=... commit -S`).
- A CI script that must not pollute global config.

If you're tempted to use `git -c` interactively, **stop and check what you're really trying to do** — usually it's bypassing a pre-commit hook, a signing requirement, or a safety check that the project added on purpose.

### Hook and safety bypasses

Don't use any of these unless the user explicitly asks:

- `--no-verify` (skips pre-commit / commit-msg hooks)
- `--no-gpg-sign` / `-c commit.gpgsign=false` (skips signing)
- `git push --force` to a protected branch
- `git push --tags` (pushes *all* local tags, including stale and experimental ones — use explicit `git push origin main v<version>` instead)

If a hook fails, the answer is to fix the underlying issue, not to skip the hook.

### Pushing tags

Always explicit:

```bash
git push origin main v<version>
```

Never `git push --tags`. Local tags accumulate stale and experimental refs over time; pushing them all is irreversible and noisy.

### Tagging on `--no-ff` merges

Tag the **merge commit on main** after the merge, not the version-bump commit on the feature branch. Late changes (review fixes, changelog tweaks) often land after the bump, and tagging the bump commit forces a delete-and-recreate later.

---

## 5. Authorization scope

Authorization is **per-request**, not session-wide.

When the user says "merge and tag," do exactly that and stop. Don't extend to push, branch deletion, or other related operations just because they're "the obvious next step." Ask explicitly if a follow-up seems worth doing.

This matters more in auto-accept and auto modes where no permission prompt will catch an over-reach.
