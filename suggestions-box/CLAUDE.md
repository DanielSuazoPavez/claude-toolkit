# Suggestions Box

Inbox for resources sent from other projects via `claude-toolkit send`.

## When Asked to "Check Suggestions"

1. List contents of this folder (excluding this file)
2. For each item, determine if it's **new** or a **modification** to an existing resource
3. Use the appropriate evaluate skill to assess quality:
   - `/evaluate-skill` for skills
   - `/evaluate-hook` for hooks
   - `/evaluate-memory` for memories
   - `/evaluate-agent` for agents
4. Consider scope: **Is this project-specific or toolkit-worthy?**
   - Project-specific patterns → reject (belongs in that project only)
   - Generally useful patterns → accept for toolkit
5. Present findings and recommendations to the user for decision

## File Types

### Resources
Files arrive as: `<name>-<TYPE>.md` (e.g., `draft-pr-SKILL.md`). Evaluate quality, consider scope (project-specific vs toolkit-worthy), present recommendations.

### Issues
Files arrive as: `<timestamp>_issue.txt` — feedback, bug reports, or improvement requests from other projects. Triage into the BACKLOG.md (or reject if not actionable).

Organized by source project in subdirectories when `--project` is specified.

## After Review (with user approval)

### Resources
- **Accept (new)**: Move to appropriate `.claude/` location, update index and MANIFEST
- **Accept (modification)**: Merge changes into existing resource
- **Modify**: Edit first, then accept
- **Reject**: Delete

### Issues
- **Accept**: Add to BACKLOG.md, delete the issue file
- **Reject**: Delete
