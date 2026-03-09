#!/usr/bin/env bash
# Backup Claude Code transcripts to preserve them from auto-pruning.
# Uses rsync so deleted files in source are kept in backup.

SRC="$HOME/.claude/projects/"
DEST="$HOME/backups/claude-transcripts/"

mkdir -p "$DEST"
rsync -a "$SRC" "$DEST"
