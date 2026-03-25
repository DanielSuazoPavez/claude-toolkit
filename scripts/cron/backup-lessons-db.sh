#!/usr/bin/env bash
# Backup lessons.db with timestamped copies and 30-day retention.
# Intended to run as a daily cron job.
#
# Crontab entry:
#   0 3 * * * /home/hata/projects/personal/claude-toolkit/scripts/cron/backup-lessons-db.sh

set -euo pipefail

SRC="$HOME/.claude/lessons.db"
DEST="$HOME/backups/claude-lessons"

[ -f "$SRC" ] || exit 0

mkdir -p "$DEST"
cp "$SRC" "$DEST/lessons_$(date +%Y%m%d_%H%M%S).db"

# Prune backups older than 30 days
find "$DEST" -name "lessons_*.db" -mtime +30 -delete
