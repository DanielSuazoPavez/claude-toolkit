#!/usr/bin/env bash
# Incrementally index Claude Code session transcripts into SQLite.
# Intended to run as a cron job alongside backup-transcripts.sh.
#
# Crontab entry (run 5 min after backup to let rsync finish):
#   5 * * * * /home/hata/projects/personal/claude-toolkit/scripts/cron/index-sessions.sh

set -euo pipefail

export PATH="$HOME/.cargo/bin:$PATH"

cd /home/hata/projects/personal/claude-sessions
uv run claude-sessions index
echo "$(date -Iseconds) index-sessions: ok"
