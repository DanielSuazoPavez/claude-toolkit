#!/usr/bin/env bash
# Format a changelog entry for raiz Telegram notification.
#
# Extracts the entry for a given version, trims lines to raiz-relevant
# content (using the MANIFEST as source of truth), and outputs Telegram HTML.
#
# Usage:
#   format-raiz-changelog.sh <version> [--raw] [--html] [--out <file>] [--override <file>]
#   format-raiz-changelog.sh 2.42.0              # default: both raw + html
#   format-raiz-changelog.sh 2.42.0 --raw        # trimmed markdown only
#   format-raiz-changelog.sh 2.42.0 --html       # telegram HTML only
#   format-raiz-changelog.sh latest               # use VERSION file
#   format-raiz-changelog.sh 2.42.0 --html --out msg.html   # write to file
#   format-raiz-changelog.sh 2.42.0 --override msg.html     # use hand-written message

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CHANGELOG="$PROJECT_ROOT/CHANGELOG.md"
MANIFEST="$PROJECT_ROOT/dist/raiz/MANIFEST"
VERSION_FILE="$PROJECT_ROOT/VERSION"

# --- argument parsing ---

VERSION=""
MODE="both"
OUT_FILE=""
OVERRIDE_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --raw|--html) MODE="$1"; shift ;;
    --out) OUT_FILE="$2"; shift 2 ;;
    --override) OVERRIDE_FILE="$2"; shift 2 ;;
    -*) echo "Unknown flag: $1" >&2; exit 1 ;;
    *) VERSION="$1"; shift ;;
  esac
done

if [[ -z "$VERSION" ]]; then
  echo "Usage: format-raiz-changelog.sh <version|latest> [--raw|--html] [--out <file>] [--override <file>]" >&2
  exit 1
fi

if [[ "$VERSION" == "latest" ]]; then
  VERSION="$(cat "$VERSION_FILE")"
fi

# Strip leading v if present
VERSION="${VERSION#v}"

# --- build resource keywords from MANIFEST ---

build_keywords() {
  local keywords=()

  # Always match these
  keywords+=("raiz")

  while IFS= read -r line; do
    line="${line%%#*}"     # strip comments
    line="${line// /}"     # strip whitespace
    [[ -z "$line" ]] && continue

    case "$line" in
      skills/*)
        # skills/brainstorm-idea/ → brainstorm-idea
        name="${line#skills/}"
        name="${name%/}"
        keywords+=("$name")
        ;;
      agents/*)
        # agents/code-debugger.md → code-debugger
        name="${line#agents/}"
        name="${name%.md}"
        keywords+=("$name")
        ;;
      hooks/*)
        # hooks/git-safety.sh → git-safety
        name="${line#hooks/}"
        name="${name%.sh}"
        # skip lib/ entries
        [[ "$name" == lib/* ]] && continue
        keywords+=("$name")
        ;;
      docs/*)
        # docs/essential-conventions-code_style.md → code_style, also full name
        name="${line#docs/}"
        name="${name%.md}"
        keywords+=("$name")
        ;;
      templates/*)
        name="${line#templates/}"
        keywords+=("$name")
        ;;
      scripts/*)
        name="${line#scripts/}"
        keywords+=("$name")
        ;;
    esac
  done < "$MANIFEST"

  # Output as pipe-separated regex pattern
  local IFS='|'
  echo "${keywords[*]}"
}

KEYWORDS="$(build_keywords)"

# --- extract changelog entry for version ---

extract_entry() {
  local version="$1"
  local in_entry=false
  local found=false

  while IFS= read -r line; do
    if [[ "$line" =~ ^##\ \[([0-9]+\.[0-9]+\.[0-9]+)\] ]]; then
      if [[ "${BASH_REMATCH[1]}" == "$version" ]]; then
        in_entry=true
        found=true
        echo "$line"
        continue
      elif $in_entry; then
        break
      fi
    fi
    $in_entry && echo "$line"
  done < "$CHANGELOG"

  if ! $found; then
    echo "Error: version $version not found in CHANGELOG.md" >&2
    return 1
  fi
}

# --- trim entry to raiz-relevant lines ---

trim_for_raiz() {
  local raw_entry="$1"
  local header=""
  local current_section=""
  local section_lines=()
  local output=""

  # First line is the version header — always keep
  header="$(echo "$raw_entry" | head -1)"
  output="$header"

  flush_section() {
    if [[ -n "$current_section" && ${#section_lines[@]} -gt 0 ]]; then
      output+=$'\n\n'"$current_section"
      for sline in "${section_lines[@]}"; do
        output+=$'\n'"$sline"
      done
    fi
    section_lines=()
  }

  while IFS= read -r line; do
    # Section header (### Added, ### Changed, etc.)
    if [[ "$line" =~ ^###\  ]]; then
      flush_section
      current_section="$line"
      continue
    fi

    # Blank line — skip
    [[ -z "${line// /}" ]] && continue

    # Bullet line — check relevance
    if [[ "$line" =~ ^-\  ]]; then
      # Match **dist** lines, or lines containing any MANIFEST resource keyword
      if echo "$line" | grep -qiE "($KEYWORDS)"; then
        section_lines+=("$line")
      fi
    fi
  done <<< "$(echo "$raw_entry" | tail -n +2)"

  flush_section
  echo "$output"
}

# --- convert trimmed markdown to Telegram HTML ---

to_telegram_html() {
  local trimmed="$1"
  local version_line desc_line body html_body

  # Parse version header: ## [X.Y.Z] - DATE - Description
  version_line="$(echo "$trimmed" | head -1)"
  local version_num date_str description
  if [[ "$version_line" =~ ^##\ \[([0-9.]+)\]\ -\ ([0-9-]+)\ -\ (.+)$ ]]; then
    version_num="${BASH_REMATCH[1]}"
    date_str="${BASH_REMATCH[2]}"
    description="${BASH_REMATCH[3]}"
  else
    echo "Error: could not parse version header" >&2
    return 1
  fi

  body="$(echo "$trimmed" | tail -n +2)"

  # Escape HTML entities in body
  html_body="$(echo "$body" \
    | sed 's/&/\&amp;/g' \
    | sed 's/</\&lt;/g' \
    | sed 's/>/\&gt;/g')"

  # Convert markdown formatting to HTML
  html_body="$(echo "$html_body" \
    | sed 's/^### \(.*\)/<b>\1<\/b>/' \
    | sed 's/^- \*\*\([^*]*\)\*\*/<b>\1<\/b>/' \
    | sed 's/`\([^`]*\)`/<code>\1<\/code>/g' \
    | sed 's/^- /• /')"

  # Build message
  local msg
  msg="🔄 <b>claude-toolkit-raiz</b> v${version_num}"
  msg+=$'\n'"<i>${date_str} — ${description}</i>"
  if [[ -n "${html_body// /}" ]]; then
    msg+=$'\n'"${html_body}"
  fi

  echo "$msg"
}

# --- output helper ---

emit() {
  local text="$1"
  if [[ -n "$OUT_FILE" ]]; then
    echo "$text" > "$OUT_FILE"
    echo "Wrote ${#text} chars to $OUT_FILE" >&2
  else
    echo "$text"
  fi
}

# --- main ---

# Override: use a hand-written message file as-is
if [[ -n "$OVERRIDE_FILE" ]]; then
  if [[ ! -f "$OVERRIDE_FILE" ]]; then
    echo "Error: override file not found: $OVERRIDE_FILE" >&2
    exit 1
  fi
  emit "$(cat "$OVERRIDE_FILE")"
  exit 0
fi

ENTRY="$(extract_entry "$VERSION")"
TRIMMED="$(trim_for_raiz "$ENTRY")"

# Check if anything survived the trim
BODY_LINES="$(echo "$TRIMMED" | tail -n +2 | grep -c '.' || true)"
if [[ "$BODY_LINES" -eq 0 ]]; then
  echo "(no raiz-relevant changes in v${VERSION})" >&2
  exit 0
fi

case "$MODE" in
  --raw)
    emit "$TRIMMED"
    ;;
  --html)
    emit "$(to_telegram_html "$TRIMMED")"
    ;;
  *)
    echo "=== Trimmed Markdown ==="
    echo "$TRIMMED"
    echo
    echo "=== Telegram HTML ==="
    to_telegram_html "$TRIMMED"
    echo
    echo "=== Stats ==="
    FULL_LINES="$(echo "$ENTRY" | grep -c '^- ' || true)"
    KEPT_LINES="$(echo "$TRIMMED" | grep -c '^- ' || true)"
    HTML="$(to_telegram_html "$TRIMMED")"
    echo "Full entry: $FULL_LINES bullet lines"
    echo "After trim: $KEPT_LINES bullet lines"
    echo "Message length: ${#HTML} chars (limit: 4096)"
    ;;
esac
