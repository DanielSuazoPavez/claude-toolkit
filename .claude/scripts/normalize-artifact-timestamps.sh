#!/usr/bin/env bash
#
# Normalize artifact filename timestamps to YYYYMMDDTHHMM__<source>__<slug>.md
# (the convention in .claude/docs/relevant-toolkit-artifacts.md).
#
# Usage:
#     .claude/scripts/normalize-artifact-timestamps.sh [--apply] [root]
#
#     root defaults to output/claude-toolkit
#     --dry-run (default): print planned renames, change nothing
#     --apply: perform renames (uses git mv if tracked, mv otherwise)
#
# Patterns recognized (legacy → target):
#     YYYYMMDD_HHMM__rest      → YYYYMMDDTHHMM__rest
#     YYYYMMDD_HHMMSS__rest    → YYYYMMDDTHHMM__rest         (drops seconds)
#     YYYYMMDD__rest           → YYYYMMDDT0000__rest
#     YYYY-MM-DD_HHMM__rest    → YYYYMMDDTHHMM__rest
#     YYYY-MM-DD__rest         → YYYYMMDDT0000__rest
#     YYYYMMDDTHHMM__...       → skip (already normalized)
#
# Anything else is logged as [skip] (whimsy plan names, BACKLOG.md, TEMPLATE.md
# — out of scope for this script; the future plan-name normalization hook owns them).
#
# Idempotent: a second run is a no-op.

set -euo pipefail

apply=false
root="output/claude-toolkit"

for arg in "$@"; do
    case "$arg" in
        --apply)   apply=true ;;
        --dry-run) apply=false ;;
        -*)        echo "Unknown flag: $arg" >&2; exit 2 ;;
        *)         root="$arg" ;;
    esac
done

if [[ ! -d "$root" ]]; then
    echo "Error: root not found: $root" >&2
    exit 1
fi

mode_label=$([[ "$apply" == true ]] && echo "APPLY" || echo "DRY-RUN")
echo "[$mode_label] root=$root"

renamed=0
skipped=0
collisions=0

# Collect files first (avoid traversal issues if we rename mid-walk).
mapfile -t files < <(find "$root" -type f -name '*.md' | sort)

for path in "${files[@]}"; do
    dir=$(dirname "$path")
    base=$(basename "$path")

    target=""
    if [[ "$base" =~ ^[0-9]{8}T[0-9]{4}__ ]]; then
        # Already normalized — skip silently.
        continue
    elif [[ "$base" =~ ^([0-9]{8})_([0-9]{4})(__.*)$ ]]; then
        target="${BASH_REMATCH[1]}T${BASH_REMATCH[2]}${BASH_REMATCH[3]}"
    elif [[ "$base" =~ ^([0-9]{8})_([0-9]{4})[0-9]{2}(__.*)$ ]]; then
        # YYYYMMDD_HHMMSS — drop the seconds.
        target="${BASH_REMATCH[1]}T${BASH_REMATCH[2]}${BASH_REMATCH[3]}"
    elif [[ "$base" =~ ^([0-9]{8})(__.*)$ ]]; then
        target="${BASH_REMATCH[1]}T0000${BASH_REMATCH[2]}"
    elif [[ "$base" =~ ^([0-9]{4})-([0-9]{2})-([0-9]{2})_([0-9]{4})(__.*)$ ]]; then
        target="${BASH_REMATCH[1]}${BASH_REMATCH[2]}${BASH_REMATCH[3]}T${BASH_REMATCH[4]}${BASH_REMATCH[5]}"
    elif [[ "$base" =~ ^([0-9]{4})-([0-9]{2})-([0-9]{2})(__.*)$ ]]; then
        target="${BASH_REMATCH[1]}${BASH_REMATCH[2]}${BASH_REMATCH[3]}T0000${BASH_REMATCH[4]}"
    else
        echo "[skip] $path"
        skipped=$((skipped + 1))
        continue
    fi

    new_path="$dir/$target"

    if [[ -e "$new_path" ]]; then
        echo "[collision] $path -> $new_path (target exists; skipping)"
        collisions=$((collisions + 1))
        continue
    fi

    echo "[rename] $base -> $target  ($dir)"
    renamed=$((renamed + 1))

    if [[ "$apply" == true ]]; then
        if git ls-files --error-unmatch "$path" >/dev/null 2>&1; then
            git mv "$path" "$new_path"
        else
            mv "$path" "$new_path"
        fi
    fi
done

echo
echo "[$mode_label] renamed=$renamed skipped=$skipped collisions=$collisions"

# Validation pass: list anything left that doesn't match the canonical form,
# excluding known non-artifact basenames.
echo
echo "=== Validation: basenames not matching ^[0-9]{8}T[0-9]{4}__ ==="
non_conforming=$(
    find "$root" -type f -name '*.md' -printf '%p\n' \
        | while read -r p; do
            b=$(basename "$p")
            if [[ "$b" =~ ^[0-9]{8}T[0-9]{4}__ ]]; then continue; fi
            if [[ "$b" == "BACKLOG.md" || "$b" == "TEMPLATE.md" ]]; then continue; fi
            echo "$p"
          done
)

if [[ -z "$non_conforming" ]]; then
    echo "(none — all artifacts conform or are known exceptions)"
else
    echo "$non_conforming"
    echo
    echo "Note: whimsy plan names (e.g., dapper-sparking-torvalds.md) are pre-convention"
    echo "and out of scope here — the plan-name normalization hook will handle them."
fi
