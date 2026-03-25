#!/usr/bin/env bash
# Incrementally index Claude Code session transcripts into SQLite.
# Intended to run as a cron job alongside backup-transcripts.sh.
#
# Crontab entry (run 5 min after backup to let rsync finish):
#   5 * * * * /home/hata/projects/personal/claude-toolkit/scripts/cron/index-sessions.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

cd "$SCRIPT_DIR/../.."
uv run scripts/sessions/index.py index
echo "$(date -Iseconds) index-sessions: ok"
