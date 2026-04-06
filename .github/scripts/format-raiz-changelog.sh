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
#   format-raiz-changelog.sh 2.45.1 --from 2.44.2 --html    # all versions after 2.44.2 up to 2.45.1

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CHANGELOG="$PROJECT_ROOT/CHANGELOG.md"
MANIFEST="$PROJECT_ROOT/dist/raiz/MANIFEST"
VERSION_FILE="$PROJECT_ROOT/VERSION"

# --- argument parsing ---

VERSION=""
FROM_VERSION=""
MODE="both"
OUT_FILE=""
OVERRIDE_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --raw|--html) MODE="$1"; shift ;;
    --out) OUT_FILE="$2"; shift 2 ;;
    --override) OVERRIDE_FILE="$2"; shift 2 ;;
    --from) FROM_VERSION="${2#v}"; shift 2 ;;
    -*) echo "Unknown flag: $1" >&2; exit 1 ;;
    *) VERSION="$1"; shift ;;
  esac
done

if [[ -z "$VERSION" ]]; then
  echo "Usage: format-raiz-changelog.sh <version|latest> [--raw|--html] [--out <file>] [--from <version>]" >&2
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

# --- list versions in range (from_version, to_version] ---
# Returns versions in changelog order (newest first).

list_versions_in_range() {
  local from="$1" to="$2"
  local collecting=false
  local versions=()

  # Same version → empty range (nothing between X and X)
  [[ "$from" == "$to" ]] && return 0

  while IFS= read -r line; do
    if [[ "$line" =~ ^##\ \[([0-9]+\.[0-9]+\.[0-9]+)\] ]]; then
      local v="${BASH_REMATCH[1]}"
      if [[ "$v" == "$to" ]]; then
        collecting=true
        versions+=("$v")
        continue
      fi
      if [[ "$v" == "$from" ]]; then
        break
      fi
      $collecting && versions+=("$v")
    fi
  done < "$CHANGELOG"

  printf '%s\n' "${versions[@]}"
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

# Build list of versions to process
VERSIONS_TO_PROCESS=()
if [[ -n "$FROM_VERSION" ]]; then
  while IFS= read -r v; do
    [[ -n "$v" ]] && VERSIONS_TO_PROCESS+=("$v")
  done < <(list_versions_in_range "$FROM_VERSION" "$VERSION")
else
  VERSIONS_TO_PROCESS=("$VERSION")
fi

if [[ ${#VERSIONS_TO_PROCESS[@]} -eq 0 ]]; then
  echo "(no versions found between $FROM_VERSION and $VERSION)" >&2
  exit 0
fi

# Process each version: use override file if it exists, otherwise extract+trim
COMBINED_TRIMMED=""
COMBINED_HTML=""

for v in "${VERSIONS_TO_PROCESS[@]}"; do
  override_path="$PROJECT_ROOT/dist/raiz/changelog/${v}.html"

  if [[ -f "$override_path" ]]; then
    echo "Using override for v${v}: $override_path" >&2
    COMBINED_HTML+="$(cat "$override_path")"$'\n\n'
    # For raw output, extract+trim as usual
    entry="$(extract_entry "$v" 2>/dev/null)" || continue
    trimmed="$(trim_for_raiz "$entry")"
    body_lines="$(echo "$trimmed" | tail -n +2 | grep -c '.' || true)"
    [[ "$body_lines" -gt 0 ]] && COMBINED_TRIMMED+="$trimmed"$'\n\n'
  else
    entry="$(extract_entry "$v" 2>/dev/null)" || { echo "Skipping v${v}: not found in CHANGELOG.md" >&2; continue; }
    trimmed="$(trim_for_raiz "$entry")"
    body_lines="$(echo "$trimmed" | tail -n +2 | grep -c '.' || true)"
    if [[ "$body_lines" -eq 0 ]]; then
      echo "Skipping v${v}: no raiz-relevant changes" >&2
      continue
    fi
    COMBINED_TRIMMED+="$trimmed"$'\n\n'
    COMBINED_HTML+="$(to_telegram_html "$trimmed")"$'\n\n'
  fi
done

# Strip trailing whitespace
COMBINED_TRIMMED="$(echo "$COMBINED_TRIMMED" | sed -e :a -e '/^[[:space:]]*$/d;N;ba')"
COMBINED_HTML="$(echo "$COMBINED_HTML" | sed -e :a -e '/^[[:space:]]*$/d;N;ba')"

if [[ -z "${COMBINED_TRIMMED// /}" && -z "${COMBINED_HTML// /}" ]]; then
  echo "(no raiz-relevant changes in range)" >&2
  exit 0
fi

case "$MODE" in
  --raw)
    emit "$COMBINED_TRIMMED"
    ;;
  --html)
    emit "$COMBINED_HTML"
    ;;
  *)
    echo "=== Trimmed Markdown ==="
    echo "$COMBINED_TRIMMED"
    echo
    echo "=== Telegram HTML ==="
    echo "$COMBINED_HTML"
    echo
    echo "=== Stats ==="
    FULL_LINES=0
    KEPT_LINES=0
    for v in "${VERSIONS_TO_PROCESS[@]}"; do
      entry="$(extract_entry "$v" 2>/dev/null)" || continue
      trimmed="$(trim_for_raiz "$entry")"
      FULL_LINES=$(( FULL_LINES + $(echo "$entry" | grep -c '^- ' || true) ))
      KEPT_LINES=$(( KEPT_LINES + $(echo "$trimmed" | grep -c '^- ' || true) ))
    done
    echo "Versions: ${#VERSIONS_TO_PROCESS[@]} (${VERSIONS_TO_PROCESS[*]})"
    echo "Full entry: $FULL_LINES bullet lines"
    echo "After trim: $KEPT_LINES bullet lines"
    echo "Message length: ${#COMBINED_HTML} chars (limit: 4096)"
    ;;
esac
