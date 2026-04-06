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
PROJECT_ROOT="${FORMAT_RAIZ_PROJECT_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
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

# --- parse version header ---

parse_version_header() {
  local header_line="$1"
  PARSED_VERSION="" PARSED_DATE="" PARSED_DESC=""
  if [[ "$header_line" =~ ^##\ \[([0-9.]+)\]\ -\ ([0-9-]+)\ -\ (.+)$ ]]; then
    PARSED_VERSION="${BASH_REMATCH[1]}"
    PARSED_DATE="${BASH_REMATCH[2]}"
    PARSED_DESC="${BASH_REMATCH[3]}"
  fi
}

# --- group bullets by resource type ---
# Input: multi-line trimmed markdown (all versions concatenated).
# Output: grouped sections (Skills, Agents, etc.) with • bullets.

group_bullets_by_resource() {
  local input="$1"
  local skills="" agents="" hooks="" docs="" scripts="" templates="" other=""

  while IFS= read -r line; do
    # Only process bullet lines
    [[ "$line" =~ ^-\  ]] || continue

    # Classify by bold prefix: - **type**: body
    if [[ "$line" =~ ^-\ \*\*([^*]+)\*\*:\ (.*)$ ]]; then
      local rtype="${BASH_REMATCH[1]}"
      local body="${BASH_REMATCH[2]}"
      case "$rtype" in
        skills)     skills+="• ${body}"$'\n' ;;
        agents)     agents+="• ${body}"$'\n' ;;
        hooks)      hooks+="• ${body}"$'\n' ;;
        docs)       docs+="• ${body}"$'\n' ;;
        scripts)    scripts+="• ${body}"$'\n' ;;
        templates)  templates+="• ${body}"$'\n' ;;
        *)          other+="• ${body}"$'\n' ;;
      esac
    else
      # No bold prefix — strip leading "- " and put in Other
      other+="• ${line#- }"$'\n'
    fi
  done <<< "$input"

  # Emit sections in fixed order, skip empty
  local output=""
  local first=true
  for pair in "Skills:$skills" "Agents:$agents" "Hooks:$hooks" "Docs:$docs" "Scripts:$scripts" "Templates:$templates" "Other:$other"; do
    local name="${pair%%:*}"
    local bullets="${pair#*:}"
    if [[ -n "$bullets" ]]; then
      $first || output+=$'\n'
      first=false
      output+="${name}"$'\n'
      output+="${bullets}"
    fi
  done

  echo -n "$output"
}

# --- convert grouped text to Telegram HTML ---

to_telegram_html() {
  local grouped="$1"
  local version="$2"
  local from_version="${3:-}"
  local date_str="${4:-}"
  local description="${5:-}"

  # Build header
  local msg
  if [[ -n "$from_version" ]]; then
    msg="🔄 <b>claude-toolkit-raiz</b> v${from_version} → v${version}"
  else
    msg="🔄 <b>claude-toolkit-raiz</b> v${version}"
    if [[ -n "$date_str" && -n "$description" ]]; then
      msg+=$'\n'"<i>${date_str} — ${description}</i>"
    fi
  fi

  # HTML-escape body (entities first, before adding tags)
  local html_body
  html_body="$(echo "$grouped" \
    | sed 's/&/\&amp;/g' \
    | sed 's/</\&lt;/g' \
    | sed 's/>/\&gt;/g')"

  # Convert section headers to bold (lines that aren't bullets)
  # Convert backticks to code tags
  html_body="$(echo "$html_body" \
    | sed '/^•/!{ /^$/!s/.*/<b>&<\/b>/; }' \
    | sed 's/`\([^`]*\)`/<code>\1<\/code>/g')"

  if [[ -n "${html_body// /}" ]]; then
    msg+=$'\n\n'"${html_body}"
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

# Auto-override: check for override file for the TARGET version only
OVERRIDE_HTML=""
override_path="$PROJECT_ROOT/dist/raiz/changelog/${VERSION}.html"
if [[ -f "$override_path" ]]; then
  echo "Using override for v${VERSION}: $override_path" >&2
  OVERRIDE_HTML="$(cat "$override_path")"
fi

# Collect trimmed content across all versions
COMBINED_TRIMMED=""
ALL_BULLETS=""
TARGET_DATE=""
TARGET_DESC=""
HAS_CONTENT=false

for v in "${VERSIONS_TO_PROCESS[@]}"; do
  entry="$(extract_entry "$v" 2>/dev/null)" || { echo "Skipping v${v}: not found in CHANGELOG.md" >&2; continue; }
  trimmed="$(trim_for_raiz "$entry")"
  body_lines="$(echo "$trimmed" | tail -n +2 | grep -c '.' || true)"

  if [[ "$body_lines" -gt 0 ]]; then
    COMBINED_TRIMMED+="$trimmed"$'\n\n'
    ALL_BULLETS+="$(echo "$trimmed" | tail -n +2)"$'\n'
    HAS_CONTENT=true
  else
    echo "Skipping v${v}: no raiz-relevant changes" >&2
  fi

  # Capture date/description for the target version (used in single-version header)
  if [[ "$v" == "$VERSION" ]]; then
    parse_version_header "$(echo "$trimmed" | head -1)"
    TARGET_DATE="$PARSED_DATE"
    TARGET_DESC="$PARSED_DESC"
  fi
done

# Strip trailing whitespace from raw output
COMBINED_TRIMMED="$(echo "$COMBINED_TRIMMED" | sed -e :a -e '/^[[:space:]]*$/d;N;ba')"

# Generate HTML (unless override already provides it)
COMBINED_HTML=""
if [[ -n "$OVERRIDE_HTML" ]]; then
  COMBINED_HTML="$OVERRIDE_HTML"
elif $HAS_CONTENT; then
  GROUPED="$(group_bullets_by_resource "$ALL_BULLETS")"
  COMBINED_HTML="$(to_telegram_html "$GROUPED" "$VERSION" "$FROM_VERSION" "$TARGET_DATE" "$TARGET_DESC")"
fi

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
